#include "ThreadTimer.hpp"

#include "Utils/Logging.h"

#include <algorithm>
#include <cassert>

using namespace wallpaper;
using micros = std::chrono::microseconds;

ThreadTimer::ThreadTimer(std::function<void()> cb)
    : m_callback(std::move(cb)),
      m_interval(micros(0)),
      m_running(false) {}
ThreadTimer::~ThreadTimer() { Stop(); }

bool ThreadTimer::Running() const { return m_running; }

void ThreadTimer::SetInterval(micros v) {
    m_interval = v;
    // The wait already in progress has to see this. A clock paced to slow
    // content sits in a long wait by design; if a tighter content rate or a
    // higher target FPS could not cut that wait short, every frame produced
    // during the remainder of it is superseded before it is ever displayed.
    std::unique_lock<std::mutex> lock(m_cond_mutex);
    m_condition.notify_all();
}

void ThreadTimer::SetMinInterval(micros v) {
    m_min_interval = v;
    // A ceiling that just got looser has to shorten a wait taken under the old
    // one; a tighter ceiling is picked up on the next re-check either way.
    std::unique_lock<std::mutex> lock(m_cond_mutex);
    m_condition.notify_all();
}

void ThreadTimer::SetIdle(bool idle) {
    std::unique_lock<std::mutex> lock(m_cond_mutex);
    if (m_idle == idle) return;
    m_idle = idle;
    // Leaving idle has to rebase the cadence, or the thread would compare now
    // against a deadline from before the scene went quiet and fire a burst of
    // ticks to "catch up" on time when nothing was being drawn. A pending
    // appointment is dropped with it: the cadence supersedes it.
    if (! idle) {
        m_rebase = true;
        m_wake_at.reset();
    }
    // Without this the thread keeps whatever wait it is already in: entering
    // idle would not take effect until the pending deadline, and leaving idle
    // would never take effect at all, because an idle wait has no deadline.
    m_condition.notify_all();
}

bool ThreadTimer::Idle() const {
    std::unique_lock<std::mutex> lock(m_cond_mutex);
    return m_idle;
}

void ThreadTimer::WakeOnce() {
    std::unique_lock<std::mutex> lock(m_cond_mutex);
    // A second request before the tick consumes the first changes nothing: the
    // latch is already set, and another notify cannot move a deadline that is
    // already the ceiling. A continuous clock already running at that ceiling
    // has the same property — the request is absorbed by the next tick — so it
    // is latched without waking the thread at all.
    if (m_wake_once || (!m_idle && m_interval.load() <= m_min_interval.load())) {
        m_wake_once = true;
        return;
    }
    m_wake_once = true;
    m_condition.notify_all();
}

void ThreadTimer::WakeAt(std::chrono::steady_clock::time_point when) {
    std::unique_lock<std::mutex> lock(m_cond_mutex);
    m_wake_at = when;
    m_condition.notify_all();
}

void ThreadTimer::FireNow() {
    std::unique_lock<std::mutex> lock(m_cond_mutex);
    m_fire_now = true;
    m_condition.notify_all();
}

void ThreadTimer::Start() {
    std::unique_lock<std::mutex> lock(m_op_mutex);

    if (Running()) return;
    m_running = true;
    m_timer_thread = std::thread([this]() {
        LOG_INFO("thread timer started");
        // The deadline is derived from the last tick and the *current*
        // interval, recomputed on every wake, so an interval that shrank moves
        // the deadline closer and one that grew moves it out. Waking early is
        // not a tick: the loop re-checks the deadline instead.
        auto last_tick = std::chrono::steady_clock::now();
        while (Running()) {
            // When the tick about to run was due. A cadence tick is anchored to
            // its deadline, not to when the thread happened to wake: taking the
            // wake time added every wait's 2-4 ms of timer slack to the period,
            // so a 60 fps ceiling delivered about 50 frames a second and 120
            // about 100. A tick more than a whole interval late restarts the
            // cadence from now rather than bursting to catch up.
            auto tick_at = std::chrono::steady_clock::now();
            {
                std::unique_lock<std::mutex> lock(m_cond_mutex);
                while (Running()) {
                    if (m_rebase) {
                        m_rebase = false;
                        last_tick = std::chrono::steady_clock::now();
                    }
                    if (m_fire_now) {
                        // The frame owed a dropped tick: the cadence restarts
                        // here, so the next tick is a whole interval away.
                        m_fire_now = false;
                        m_wake_once = false;
                        tick_at = std::chrono::steady_clock::now();
                        break;
                    }
                    // The user's FPS ceiling is a floor on the gap between two
                    // callbacks, and it binds every path into one — not only
                    // the cadence. The cadence alone cannot carry it: content
                    // pacing makes `m_interval` *longer* than the ceiling, so
                    // an interval of 1s says nothing about how close together
                    // two event-driven frames may run.
                    //
                    // Before this, a one-shot request was honoured immediately
                    // whenever the clock was idle, so anything that asks for a
                    // frame — pointer movement, at the pointer sample rate —
                    // drove the scene at the rate the events arrived at rather
                    // than at the rate the user configured.
                    const auto earliest = last_tick + m_min_interval.load();

                    if (m_idle) {
                        // An idle clock has no cadence, so the only deadlines
                        // are the ones something asked for. A request is due at
                        // the ceiling: after a long sleep that moment is
                        // already past and the frame runs at once, and during a
                        // burst the requests coalesce into one frame per
                        // period instead of one frame each.
                        std::optional<std::chrono::steady_clock::time_point> due;
                        if (m_wake_once) {
                            due = earliest;
                        } else if (m_wake_at.has_value()) {
                            // An appointment already past is owed, not urgent:
                            // clamping it to the ceiling is what stops a
                            // deadline that keeps being re-armed in the past
                            // from spinning the thread.
                            due = std::max(*m_wake_at, earliest);
                        }
                        if (! due.has_value()) {
                            // No deadline at all. This is the difference
                            // between an idle scene and a slow one: a slow
                            // scene still wakes to find nothing to do.
                            m_condition.wait(lock);
                            continue;
                        }
                        const auto now = std::chrono::steady_clock::now();
                        if (now >= *due) {
                            // An event-driven frame has no cadence to keep.
                            tick_at = now;
                            m_wake_once = false;
                            // Only a kept appointment is consumed. One that is
                            // still in the future survives a frame that ran for
                            // another reason, so a layer that asked to redraw
                            // on the minute still redraws on the minute.
                            if (m_wake_at.has_value() && now >= *m_wake_at) m_wake_at.reset();
                            break;
                        }
                        m_condition.wait_until(lock, *due);
                        continue;
                    }

                    auto deadline = last_tick + m_interval.load();
                    // A pending request may cut a long content-paced wait
                    // short, because the event is new content the period did
                    // not predict — but only as far as the ceiling, never past
                    // it. When the cadence is the ceiling this changes nothing.
                    if (m_wake_once && earliest < deadline) deadline = earliest;
                    const auto now = std::chrono::steady_clock::now();
                    if (now >= deadline) {
                        // Late by more than the step this deadline took — the
                        // interval, or the ceiling when a request cut the wait
                        // short — restarts from now, so an old anchor cannot
                        // let requests through faster than the ceiling.
                        tick_at = now - deadline < deadline - last_tick ? deadline : now;
                        // The tick satisfies any pending request: the frame it
                        // is about to run is the frame that was asked for.
                        // Clearing here rather than discarding at the request
                        // site is what keeps the latch meaningful — a request
                        // is never dropped, only absorbed by a real frame.
                        m_wake_once = false;
                        break;
                    }
                    m_condition.wait_until(lock, deadline);
                }
            }
            if (!Running()) break;
            last_tick = tick_at;
            if (m_callback) m_callback();
        }
        LOG_INFO("thread timer exited");
    });
}

void ThreadTimer::Stop() {
    std::unique_lock<std::mutex> lock(m_op_mutex);
    assert(std::this_thread::get_id() != m_timer_thread.get_id());

    if (! Running()) return;
    m_running = false;
    LOG_INFO("thread timer stopping");

    {
        std::unique_lock<std::mutex> lock(m_cond_mutex);
        m_condition.notify_all();
    }

    if (m_timer_thread.joinable()) {
        m_timer_thread.join();
    }
}
