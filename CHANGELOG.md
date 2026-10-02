# Changelog

Every published version, newest first. Each section is written when its version is
cut, by [`scripts/release_notes.py`](scripts/release_notes.py) from the commits
between two version tags: a language model writes them up for users, where older
sections list the commits. Each section states the same notes in English and
Simplified Chinese. The app's What's New window offers both translations; the
GitHub Release body repeats only the English notes. See
[docs/release.md](docs/release.md) for how a version is cut.

## 1.2.3 — 2026-10-02

### English

SteamCMD now runs natively on Apple silicon, Workshop presets arrive with their base wallpapers, and many scene, web, video and multi-display problems are fixed

#### Breaking changes

- Existing Intel-only SteamCMD copies must be reinstalled from Settings → Library & Steam, and the app guides you through it

#### New

- Workshop presets can now be imported together with their base wallpaper, which downloads automatically if missing, as one self-contained library entry

#### Improved

- SteamCMD now installs and runs natively on Apple silicon without Rosetta, keeping your sign-in, saved sessions and Workshop downloads
- Download errors now recognize connection problems and rate limits instead of blaming your Steam credentials for unknown failures
- Pixiv downloads refused by the server now explain that access was denied instead of suggesting that a short wait will help

#### Fixed

- A deleted wallpaper assigned to one display no longer stops wallpapers from applying on other displays, and reinstalling it restores the assignment
- Web wallpapers that load WebAssembly from their own files, such as those built with Unity, now start correctly
- Video wallpapers in formats macOS cannot open itself, such as MKV, are no longer rejected and now try compatibility playback
- Scenes whose camera parallax has no delay no longer show a flat grey screen and now follow the cursor immediately
- With Compatibility rendering, some layers no longer show another layer's picture, such as a stained-glass window turning dark
- Web wallpapers that react to music now receive audio even when no scene wallpaper is running
- Brightness pulse effects in some scenes now stay inside the areas their authors intended instead of spreading across the picture
- When the experimental animated lock screen fails to start, your screen saver setting is now kept instead of being changed
- The frame rate slider in Performance can now cap at your display's full refresh rate, with No limit as its own position

### 简体中文

SteamCMD 现可在 Apple 芯片上原生运行，Workshop 预设会连同其基础壁纸一起导入，同时修复了场景、网页、视频和多显示器方面的诸多问题

#### 不兼容变更

- 现有的仅限 Intel 的 SteamCMD 需要在设置 → 壁纸库与 Steam 中重新安装，应用会引导你完成

#### 新增

- 现在可以将 Workshop 预设连同其基础壁纸一起导入，缺少的基础壁纸会自动下载，并合成为一个独立的壁纸库条目

#### 改进

- SteamCMD 现可在 Apple 芯片上原生安装和运行，无需 Rosetta，并保留你的登录状态、已保存会话和 Workshop 下载
- 下载错误现在能识别网络连接问题和频率限制，不再把未知故障归咎于你的 Steam 账号凭据
- 被服务器拒绝的 pixiv 下载现在会说明访问被拒绝，而不是提示稍等片刻即可解决

#### 修复

- 分配给某个显示器的壁纸被删除后不再导致其他显示器无法应用壁纸，重新安装该壁纸即可恢复分配
- 从自身文件加载 WebAssembly 的网页壁纸（例如使用 Unity 制作的壁纸）现在可以正常启动
- macOS 自身无法打开的视频壁纸格式（例如 MKV）不再被拒绝，现在会尝试使用兼容播放
- 相机视差没有延迟的场景不再显示为一片灰屏，现在会立即跟随光标移动
- 使用兼容渲染时，部分图层不再显示其他图层的画面，例如彩色玻璃窗变暗的问题
- 随音乐变化的网页壁纸现在即使没有运行场景壁纸也能获取音频
- 部分场景中的亮度脉冲效果现在会保持在作者设定的区域内，不再扩散到整个画面
- 实验性的动态锁定屏幕启动失败时，现在会保留你的屏幕保护程序设置，而不会将其更改
- 性能中的帧率滑块现在可以限制在显示器的完整刷新率，“无限制”单独作为一个档位

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v1.2.2...v1.2.3

## 1.2.2 — 2026-10-01

### English

This release adds wallpaper collections, playlists, presets and settings backups, and fixes several problems with restoring your original desktop and lock screen wallpapers

#### Breaking changes

- Workshop downloads now require a Steam account that owns Wallpaper Engine, and you can check again after buying it

#### New

- Organize installed wallpapers into your own collections and reusable playlists
- Save wallpaper properties as named presets, apply them anytime and exchange them with others
- Back up your settings and, optionally, your wallpaper files, then preview a restore before applying it and undo it if needed
- Mute web wallpapers and adjust media volume
- Position and zoom imported images separately on each display
- Choose which displays an action applies to in Shortcuts
- Wallpapers now come with an explanation of their compatibility

#### Fixed

- Quitting now restores your original wallpaper on each display and Space, even after a relaunch, and leaves the system wallpaper alone when no original can be recovered
- Quitting now waits for your original wallpaper to be restored and is cancelled with an error if restoring fails, instead of leaving a still frame behind
- After a cancelled quit, the desktop still frame resumes updating without needing another wallpaper or settings change
- The experimental animated lock screen can now be turned on when macOS shares its default wallpaper between the lock screen and screen saver
- Turning on only the experimental lock screen no longer times out when a Space inherits its wallpaper, and your screen saver choice is kept
- When lock screen wallpaper recovery fails because of damaged saved data, your wallpapers and recovery data are now kept so recovery can be retried

### 简体中文

此版本新增壁纸合集、播放列表、预设和设置备份，并修复了恢复原桌面和锁定屏幕壁纸时的多个问题

#### 不兼容变更

- Workshop 下载现在需要拥有 Wallpaper Engine 的 Steam 账户，购买后可重新检查

#### 新增

- 可将已安装的壁纸整理为自定义合集和可重复使用的播放列表
- 可将壁纸属性保存为命名预设，随时应用，并可与他人交换
- 可备份设置并选择是否包含壁纸文件，恢复前可预览，必要时还可撤销恢复
- 可将网页壁纸静音，并调节媒体音量
- 可在每台显示器上分别调整导入图片的位置和缩放
- 可在快捷指令中选择操作要应用到的显示器
- 壁纸现在附带兼容性说明

#### 修复

- 退出时会在每台显示器和每个空间恢复原壁纸，重新启动后也是如此；无法找回原壁纸时不再改动系统壁纸
- 退出时会等待原壁纸恢复完成；恢复失败时会取消退出并显示错误，不再留下静止画面
- 取消退出后，桌面静止画面会恢复更新，无需再次更换壁纸或修改设置
- 当 macOS 在锁定屏幕和屏幕保护程序之间共用默认壁纸时，现在也可以开启实验性的动态锁定屏幕
- 当空间沿用继承的壁纸时，仅开启实验性锁定屏幕不再超时，屏幕保护程序的选择也会保留
- 因保存的数据损坏导致锁定屏幕壁纸恢复失败时，现在会保留壁纸和恢复数据，以便重新尝试恢复

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v1.2.1...v1.2.2

## 1.2.1 — 2026-09-30

### English

This release adds an experimental option to use applied wallpapers as macOS screen savers, restores glow and live updates in scene wallpapers, and gives Settings a clearer, roomier layout

#### New

- Try an experimental setting on macOS 26 and later that shows applied scene, video, web and still wallpapers as screen savers and restores your previous choice when turned off
- What's New opens in a larger window with English and Simplified Chinese tabs and starts in the app's current language
- After you first apply a downloaded wallpaper, the app asks once whether you would like to star it on GitHub or become a Supporter, and is easy to dismiss

#### Improved

- All Settings pages have roomier spacing, cleaner separators and controls that stack in narrow windows, with library and installation paths shown full width
- Advanced performance controls are split into video, scene and experimental groups, with renderer choices first and running status in collapsible Live diagnostics sections
- The energy readout in Settings leads with total power and an energy grade, shows CPU and GPU separately and tucks details into an expandable section
- Workshop download errors now explain that a Steam account that purchased Wallpaper Engine is required, with guidance on buying it or switching accounts
- The experimental animated lock screen now shows a specific error when macOS loads an incompatible app copy or its configuration fails to load
- Expand and collapse arrows in Settings are bolder and easier to read, turning accent-colored when open
- The welcome guide's language picker has a balanced layout, with System (Auto) on its own row above equal language tiles

#### Fixed

- Scene wallpapers show bright glows, bloom and emissive highlights correctly again, and bloom no longer grows out of bounds
- Scene wallpapers with clocks, text, audio bars and interactive properties update live again
- Perspective scenes and full-screen effects render at the selected display resolution without losing texture detail, and translucent glows keep their backgrounds
- Scene wallpapers that rely on scripted layers, templates, hidden textures or perspective particles display their full content again
- Navigation in the control panel stays visible in full-screen and Split View, and the title bar returns normally on exit
- The Import file picker now matches the app language right after you change it, without restarting wallpapers
- The active display filter label in Installed stays on one line without being shrunk or cut off

### 简体中文

此版本新增实验性选项，可将已应用的壁纸用作 macOS 屏幕保护程序，恢复了场景壁纸的光晕效果与实时更新，并让设置页面布局更清晰、更宽松

#### 新增

- 在 macOS 26 及更高版本上可试用一项实验性设置，将已应用的场景、视频、网页和静态壁纸用作屏幕保护程序，关闭后恢复你之前的选择
- 新功能窗口现在以更大的尺寸打开，提供英文和简体中文标签页，并默认显示应用当前的语言
- 首次应用下载的壁纸后，应用会询问一次是否愿意在 GitHub 上加星或成为支持者，并且可以轻松关闭

#### 改进

- 所有设置页面的间距更宽松、分隔线更整洁，窄窗口中控件会纵向排列，壁纸库和安装路径以全宽显示
- 高级性能控件分为视频、场景和实验性三组，渲染器选项排在最前，运行状态放在可折叠的实时诊断区域中
- 设置中的能耗读数首先显示总功率和能耗等级，分别显示 CPU 和 GPU 读数，并将详细信息收进可展开的区域
- Workshop 下载出错时会说明需要已购买 Wallpaper Engine 的 Steam 账户，并提供购买或切换账户的指引
- 实验性动态锁定屏幕现在会在 macOS 加载了不兼容的应用副本或配置加载失败时显示具体错误
- 设置中的展开和折叠箭头更粗、更易辨认，展开时会显示强调色
- 欢迎向导中的语言选择器布局更均衡，“系统（自动）”单独占一行，下方为等宽的语言选项

#### 修复

- 场景壁纸重新正确显示明亮光晕、泛光和自发光高光，泛光也不再过度扩散
- 带有时钟、文字、音频条和交互属性的场景壁纸重新能够实时更新
- 透视场景和全屏效果按所选显示器分辨率渲染且不丢失纹理细节，半透明光晕后方的背景也得以保留
- 依赖脚本图层、模板、隐藏纹理或透视粒子的场景壁纸重新完整显示内容
- 控制面板的导航在全屏和分屏浏览中保持可见，退出后标题栏也会正常恢复
- 更改应用语言后，导入文件选择器会立即使用新语言，且无需重启壁纸
- 已安装中当前显示器筛选标签保持单行显示，不再被缩小或截断

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v1.2.0...v1.2.1

## 1.2.0 — 2026-09-29

### English

This release adds pixiv, playlists, Workshop updates and subscriptions, picture import, keyboard shortcuts and Shortcuts actions, and Traditional Chinese and Japanese, and makes the experimental animated lock screen more dependable.

#### New

- A new pixiv tab browses rankings and tag search with filters, and saves any illustration page to Installed as a still wallpaper
- Sign in to pixiv to see members-only works and, if your account allows it, choose to include R-18 works
- Settings → Displays gives each display a Playlist that rotates through all wallpapers, your favorites or its own list, in order or shuffled, from every 5 minutes to every day, or switches between a day and a night wallpaper
- Add wallpapers to a display's playlist from their details or a selection, and the menu bar's Next Wallpaper follows a rotating display's playlist
- Once a day the app asks Steam which of your installed Workshop wallpapers have been updated, sending only their ids; update one or all of them from Installed and they keep their settings, and Settings → Library & Steam can turn the check off
- Discover can browse Workshop collections, more wallpapers by an author and your Steam subscriptions, and download the subscribed wallpapers you don't have yet
- Import JPEG, PNG, GIF, WebP, HEIC, TIFF, BMP and AVIF pictures up to 512 MB as still wallpapers with Image fit and background colour options
- Drop files or folders on WallpaperMachine in the Dock, or open them with it from Finder, to import them
- Settings → General can record global keyboard shortcuts to play or pause wallpapers, go to the next wallpaper and open the control panel; none is set until you record one
- The Shortcuts app gains WallpaperMachine actions that Siri and Spotlight can run too, and the same commands work as wallpapermachine:// links
- Settings → Performance → Playback can pause or stop wallpapers in Low Power Mode or when the Mac is hot, off until you choose
- Add the WallpaperMachine Focus filter in System Settings to pause, mute or stop wallpapers while a Focus is on
- WallpaperMachine is now also in Traditional Chinese and Japanese, chosen in Settings → General → Language or used automatically when your Mac is set to one of them
- After an update, a What's New window lists the changes since your previous version in English and Simplified Chinese, and can be turned off

#### Fixed

- The experimental animated lock screen now resumes where it left off after the display wakes, instead of reloading and restarting its animation
- The experimental animated lock screen no longer briefly shows the background behind the wallpaper
- The experimental animated lock screen no longer clears its wallpaper when displays are connected, removed or change resolution
- A waking display shows black instead of white until its wallpaper draws again
- Wallpapers are no longer reset when a display wakes and macOS only moves their windows

### 简体中文

此版本新增 pixiv、播放列表、创意工坊更新与订阅、图片导入、键盘快捷键与快捷指令操作，以及繁体中文和日语，并让实验性的动态锁定屏幕更加可靠。

#### 新增

- 新增 pixiv 标签页，可按条件筛选浏览排行榜和标签搜索，并将任意插画页面保存到已安装，作为静态壁纸使用
- 登录 pixiv 后可查看仅限会员的作品，若账户允许，还可选择显示 R-18 作品
- 设置 → 显示器为每台显示器提供播放列表，可在全部壁纸、个人收藏或它自己的列表中按顺序或随机轮换，间隔从 5 分钟到 1 天，也可在白天和夜晚各显示一张壁纸
- 可从壁纸详情或多选中把壁纸加入显示器的播放列表，菜单栏的“下一张壁纸”会跟随正在轮换的显示器的播放列表
- 应用每天向 Steam 查询一次已安装的创意工坊壁纸是否有更新，只发送壁纸 ID；可在已安装中更新单个或全部壁纸，壁纸设置会保留，也可在 设置 → 壁纸库与 Steam 中关闭检查
- 发现页可以浏览创意工坊合集、作者的更多作品和你的 Steam 订阅，并可下载库中还没有的订阅壁纸
- 可导入最大 512 MB 的 JPEG、PNG、GIF、WebP、HEIC、TIFF、BMP 和 AVIF 图片作为静态壁纸，并可设置图像适配方式和背景颜色
- 将文件或文件夹拖到程序坞中的 WallpaperMachine 上，或在访达中用它打开，即可导入
- 设置 → 通用可录制全局键盘快捷键，用于播放或暂停壁纸、切换到下一张壁纸和打开控制面板，录制之前不会设置任何快捷键
- 快捷指令 App 新增 WallpaperMachine 操作，Siri 和聚焦搜索也能运行，同样的命令也可以通过 wallpapermachine:// 链接调用
- 设置 → 性能 → 播放新增选项，可在低电量模式下或 Mac 过热时暂停或停止壁纸，选择前默认关闭
- 在系统设置中添加 WallpaperMachine 的专注模式过滤条件，即可在专注模式开启时暂停、静音或停止壁纸
- WallpaperMachine 新增繁体中文和日语，可在 设置 → 通用 → 语言 中选择，Mac 使用这两种语言时也会自动采用
- 更新后会显示“更新内容”窗口，用中英双语列出自上个版本以来的变化，也可以关闭

#### 修复

- 实验性的动态锁定屏幕在显示器唤醒后会从中断处继续播放，不再重新加载并从头开始动画
- 实验性的动态锁定屏幕不再短暂露出壁纸下方的背景
- 连接、移除显示器或更改分辨率时，实验性的动态锁定屏幕不再清除壁纸
- 显示器唤醒时，壁纸重新绘制之前显示黑色而不是白色
- 显示器唤醒且 macOS 只是移动壁纸窗口时，壁纸不再被重置

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v1.1.0...v1.2.0

## 1.1.0 — 2026-09-28

### English

Wallpapers now pause when windows cover the desktop and use less memory, and actions queue and run in order instead of showing an error.

#### New

- Wallpapers pause when windows cover the desktop and resume once any of it shows, set in Settings → Performance → Playback with Pause as default or Keep running

#### Improved

- Actions from the control panel and menu bar now queue and run in order, and clicking several wallpapers in a row applies the last one
- The tile being applied shows a progress ring, and wallpapers queued behind it are marked
- Wallpapers use less memory by loading textures sized for your display and releasing renderers and allocations they are not using
- The experimental animated lock screen keeps a still poster while unlocked and loads its scene only when it can be shown
- Discover releases preview animations for tiles scrolled out of view, and the control panel frees its web resources when closed
- Favorites, Show in Finder and the delete confirmation no longer wait for or hold up other actions
- The default frame rate limit is now 60 fps

#### Fixed

- Switching wallpapers while another action was running no longer shows a red "Wait for the current action to finish" banner
- Frame rate limits now reach their target, where a 60 fps limit previously delivered about 50 frames a second
- Library refreshes after downloads and imports no longer fail while a wallpaper is being applied
- The Updates and license cards in Settings → About now leave the same space below their last line as other cards

### 简体中文

窗口盖住桌面时壁纸会暂停，并且占用更少内存；各项操作会排队按顺序执行，而不再显示错误。

#### 新增

- 窗口盖住桌面时壁纸会暂停，一旦桌面有任何部分露出就恢复。可在设置 → 性能 → 播放中设置，默认为“暂停”，也可选“继续运行”

#### 改进

- 控制面板和菜单栏中的操作现在会排队按顺序执行；连续点击多张壁纸时，会应用最后点的那一张
- 正在应用的磁贴会显示进度环，排在它后面的壁纸也会被标出
- 壁纸会按你的显示器尺寸加载纹理，并释放未在使用的渲染器和内存分配，从而占用更少内存
- 实验性的锁定屏幕动态壁纸在未锁定时保持一张静止海报，只在能够显示时才加载场景
- “发现”会释放滚出视野的磁贴预览动画；控制面板关闭时会释放它的网页资源
- 收藏、“在访达中显示”和删除确认不再等待其他操作，也不再挡住它们
- 默认帧率上限现在是 60 fps

#### 修复

- 在另一项操作进行中切换壁纸时，不再显示红色的“请等待当前操作完成”横幅
- 帧率上限现在能达到设定目标；以前设为 60 fps 时，大约只有每秒 50 帧
- 正在应用壁纸时，下载和导入之后的壁纸库刷新不再失败
- 设置 → 关于中的更新卡片和许可证卡片，最后一行下方现在留出与其他卡片相同的间距

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v1.0.3...v1.1.0

## 1.0.3 — 2026-09-28

### English

This release stops wallpapers from flashing and restarting after unlocking, makes Restart to Update work again, and keeps the control panel open after you apply a wallpaper.

#### Breaking changes

- Applying a wallpaper no longer hides the control panel by default; a choice already made in Settings → General → Hide window after applying a wallpaper is kept

#### New

- File → Close (Command-W) now closes the control panel, like its close button, while the app keeps running in the menu bar

#### Improved

- Apply and Quit respond promptly even while the app is handling a burst of updates, such as after unlocking the Mac
- Update checks no longer use up GitHub's hourly limit on anonymous requests, which is shared by every device on the same network

#### Fixed

- Wallpapers no longer flash white and restart their opening animation again and again after unlocking the Mac, a problem introduced in 1.0.2
- Restart to Update now quits and reopens on the new version instead of closing the window and doing nothing
- With the experimental Animate Lock Screen on, macOS 15 and later no longer asks at every launch to allow access to data from other apps
- The experimental animated lock screen keeps moving when you lock the Mac instead of showing a still frame
- Applying a wallpaper, changing a display setting or switching the video backend no longer reloads unchanged wallpapers on other displays, which made them flash white
- A wallpaper applied while a frame-rate cap is on now starts at the capped rate
- About no longer reports a connection failure when GitHub's hourly update-check limit runs out; it says when the limit resets and waits until then

### 简体中文

此版本让解锁后壁纸不再闪一下并重新开始，使“重启并更新”重新可用，并在你应用壁纸后保持控制面板打开。

#### 不兼容变更

- 应用壁纸后默认不再隐藏控制面板；若已在设置 → 通用 → 应用壁纸后隐藏窗口中做过选择，该选择会保留

#### 新增

- 文件 → 关闭（Command-W）现在会关闭控制面板，与它的关闭按钮一样，应用仍在菜单栏中继续运行

#### 改进

- 即使应用正在处理一阵密集的更新，例如解锁 Mac 之后，“应用”和“退出”也会及时响应
- 更新检查不再用尽 GitHub 对匿名请求的每小时限额；该限额由同一网络上的每台设备共享

#### 修复

- 解锁 Mac 后，壁纸不再反复闪白并重新播放开场动画；这个问题是 1.0.2 引入的
- “重启并更新”现在会退出并在新版本上重新打开，而不再只是关掉窗口、什么也不做
- 开启实验性的“锁定屏幕动态壁纸”后，macOS 15 及更高版本不再在每次启动时询问是否允许访问其他 App 的数据
- 锁定 Mac 时，实验性的锁定屏幕动态壁纸会继续播放，而不再停在一帧上
- 应用壁纸、更改显示器设置或切换视频后端时，不再重新加载其他显示器上没有变化的壁纸，那些壁纸因此不再闪白
- 在帧率上限开启时应用的壁纸，现在会以该上限速率开始
- GitHub 每小时的更新检查限额用尽时，“关于”不再报告连接失败；它会说明限额何时重置，并等到那时

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v1.0.2...v1.0.3

## 1.0.2 — 2026-09-27

### English

WallpaperMachine 1.0.2 adds drag selection in Installed, makes in-app updates safer and keeps macOS privacy permissions across updates. Wallpapers and the control panel also do less repeated and background work.

#### New

- Hold a tile in Installed and drag across others to select a run of wallpapers, with auto-scroll at the edges
- A tip in the selection row explains drag selection until you use it once or dismiss it

#### Improved

- Wallpapers skip redrawing frames that would repeat an unchanged picture, and scenes follow the Scene render optimisation setting for this
- Sound output starts only while a wallpaper is playing unmuted, and system audio is captured only for scenes or web wallpapers that use it
- Paused or covered scenes stop tracking the pointer, and web wallpapers track it only while a page is live
- Video and scene playback do less background work, with fewer decode wakes and hidden particles skipped while their simulation continues
- The control panel does less work while inactive, and Discover samples colours only while it is visible
- Reselecting the same lock screen wallpaper no longer repeats the compatibility check
- Tiles in Installed no longer enlarge on hover

#### Fixed

- Restarting to install an update no longer removes the current version first, and reopens the previous version if the install fails
- macOS privacy permissions granted to the app are no longer lost after an update
- Scene wallpapers no longer risk failing when their display surface is replaced while the scene is still loading at startup

### 简体中文

WallpaperMachine 1.0.2 在“已安装”中增加拖拽选择，让应用内更新更安全，并在更新后保留 macOS 隐私权限。壁纸和控制面板也会减少重复的工作和后台工作。

#### 新增

- 在“已安装”中按住一张磁贴并拖过其他磁贴，即可选中连续的一段壁纸，拖到边缘时会自动滚动
- 选择行里的提示会说明拖拽选择，直到你使用过一次或关掉它

#### 改进

- 壁纸会跳过只会重复未变化画面的重绘；场景是否这样做，遵循“场景渲染优化”设置
- 只有壁纸正在播放且未静音时才开始输出声音；只有使用系统音频的场景或网页壁纸才会采集它
- 已暂停或被盖住的场景不再跟踪指针；网页壁纸只在页面处于活动状态时跟踪指针
- 视频和场景播放减少后台工作：解码唤醒更少，隐藏的粒子在其模拟继续时会被跳过
- 控制面板在不活动时少做工作；“发现”只在可见时采样颜色
- 再次选择同一张锁屏壁纸时，不再重复兼容性检查
- “已安装”中的磁贴在悬停时不再放大

#### 修复

- 为安装更新而重启时，不再先移除当前版本；如果安装失败，会重新打开先前的版本
- 授予本应用的 macOS 隐私权限在更新后不再丢失
- 启动时如果场景仍在加载、其显示表面被替换，场景壁纸不再因此可能失败

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v1.0.1...v1.0.2

## 1.0.1 — 2026-09-27

### English

WallpaperMachine now checks for updates on its own, adds a rebuilt Performance page with an energy readout and battery options, and fixes a launch crash after changing the render scale.

#### New

- WallpaperMachine checks for updates after the library loads and every six hours, and where it can update in place it downloads them and offers Restart to Update
- WallpaperMachine runs on macOS 15 Sequoia
- Settings → Performance shows the app's CPU and GPU power, a grade, its share of the battery and a before/after comparison when you change a setting
- On battery you can choose to keep running, drop to a render scale and frame rate you pick, or pause, and this stays off until you choose
- Playback rules can pause or mute wallpapers while chosen apps are frontmost or another app is playing audio
- The menu bar item adds Next Wallpaper, which applies the next playable library wallpaper to the target display, and Lock Screen
- Settings → General adds Hide window after applying a wallpaper, on by default, which you can turn off to keep the window open for previewing
- The inspector shows each wallpaper's energy rating
- Settings can save a redacted diagnostics report to attach to a GitHub issue
- The welcome guide gains a Performance step

#### Improved

- Settings → Performance is rebuilt as a single page covering energy use first, then quality, then playback
- The frame-rate cap now follows the display's native refresh rate by default
- A display that goes to sleep now stops its wallpaper
- After choosing Later on an update, the menu bar item keeps offering it until the app restarts

#### Fixed

- The app no longer crashes at launch right after applying a render scale
- Reopening the app from the Dock now keeps you on the page you were viewing

### 简体中文

WallpaperMachine 现在会自行检查更新，新增了重建后的“性能”页面，带有能耗读数和电池选项，并修复了更改渲染比例后启动崩溃的问题。

#### 新增

- WallpaperMachine 会在壁纸库加载后以及每隔六小时检查更新；在能够就地更新时会下载更新，并提供“重启并更新”
- WallpaperMachine 可在 macOS 15 Sequoia 上运行
- 设置 → 性能显示本应用的 CPU 和 GPU 功耗、等级、占电池的比例，以及你更改一项设置时的前后对比
- 使用电池时，可以选择继续运行、降到你选定的渲染比例和帧率，或暂停；在你选择之前，此功能保持关闭
- 播放规则可以在所选应用位于最前，或其他应用正在播放音频时，暂停或静音壁纸
- 菜单栏项目增加了“下一张壁纸”和“锁定屏幕”。“下一张壁纸”会把壁纸库中下一张可播放的壁纸应用到目标显示器
- 设置 → 通用增加了“应用壁纸后隐藏窗口”，默认开启；可以关掉它，以便预览时保持窗口打开
- 壁纸详情显示每张壁纸的能耗等级
- 设置可以保存一份已脱敏的诊断报告，以便附到 GitHub issue
- 欢迎指南增加了一个“性能”步骤

#### 改进

- 设置 → 性能重建为单一页面，依次涵盖能耗、画质和播放
- 帧率上限现在默认跟随显示器的原生刷新率
- 进入睡眠的显示器现在会停止它的壁纸
- 在更新提示上选择“稍后”之后，菜单栏项目会一直提供该更新，直到应用重启

#### 修复

- 刚应用渲染比例之后，应用在启动时不再崩溃
- 从程序坞重新打开应用时，会留在你正在查看的页面

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v1.0.0...v1.0.1

## 1.0.0 — 2026-09-26

### English

WallpaperMachine 1.0 ships as a drag-to-install disk image and adds a first-run guide with Steam sign-in, optional now-playing support for music wallpapers and many scene rendering fixes.

#### New

- Downloads and in-app updates now come as a drag-to-install disk image with first-launch steps under System Settings → Privacy & Security → Open Anyway
- A first-run welcome guide sets language and appearance, signs in to Steam and shares tips, and can be reopened from Settings → Library & Steam
- Music wallpapers can optionally show the current track, cover art and playback state from your Mac's now-playing information once you allow media access
- Play, pause, next and previous buttons inside music wallpapers can now control the player you are using, starting on the action the button's name suggests
- Choose how many Workshop downloads run at once in Settings → Library & Steam → Downloads at once, from 1 to 6
- Settings → General has a Language picker for System (Auto), English and Simplified Chinese that switches the panel in place
- The control panel has a Wallpaper Engine-style filter sidebar with Workshop filters for type, age rating, resolution and tags, plus more Discover sort orders
- Installed can be filtered with the same sidebar boxes as Discover and sorted by name, type, favorites, file size or date added
- Wallpapers that let you choose your own picture now show the picture you pick instead of the packaged artwork
- Tiles show corner marks for staff-approved items, favorites and wallpapers already in your library
- Report a problem on GitHub now opens with the wallpaper's details filled in
- Choose between new branded app icons
- Settings → About shows what changed in the newest release
- The optional Native Metal renderer now draws effects, video, text layers, puppets, particle trails and sprite sheets

#### Improved

- Scenes with many large images open much faster because their images are decoded once and in parallel
- Newly connected displays start enabled with the main display's wallpaper, and turning one off is remembered across reconnections
- The Discover download ring names the current step, such as Connecting or Signing in, and shows Finishing while files are checked and imported
- Discover previews download once, are kept on disk and play sooner, and resizing the window no longer reloads the page
- The frame rate limit you set is now respected by wallpapers that react to the pointer
- Changing tracks on a music wallpaper no longer reloads the whole wallpaper or restarts its videos
- Heavy 3D wallpapers get more time to show their first frame, and later launches reach it faster
- Scene wallpapers do less redundant drawing work while playing
- Control panel text is rewritten in plain language and every message, menu and error is now translated into Simplified Chinese
- Checking for updates no longer reports an error when no release has been published yet

#### Fixed

- Wallpapers no longer disappear when you hide the app with Cmd-H or after activating a wallpaper
- The app restores your own wallpapers at launch instead of posters or selections inherited from another display
- Scene video textures no longer freeze after half a second, and 4K video scenes no longer fail with no first frame
- The internal render scale setting now takes effect on scene wallpapers
- Wallpaper buttons no longer stay stuck shrunk after being pressed
- Sounds bound to a wallpaper's volume slider now follow the slider
- Camera intros in 2D scenes play, and masked or parallax layers stay in place instead of sliding out of view
- 2D wallpapers with a camera layer no longer show only a small patch in one corner
- Blurred layers no longer flatten into a grey wash in the Compatibility renderer
- Effects written for Wallpaper Engine that were silently dropped now appear on their layers
- Audio-responsive elements react to sound on the Native Metal renderer instead of turning black
- Heavy 3D scenes no longer collapse to a column or lose skies, rings and large meshes
- Mouse trails follow the cursor near screen edges instead of drifting away from it
- Parallax no longer pushes grouped layers aside and uncovers what is beneath them
- Scripted dock icons in wallpapers now scale, fade and open as intended
- Album covers keep their authored shape instead of turning into circles
- Music wallpapers no longer go blank after changing a setting until playback is paused and resumed
- The lock screen status row now shows the real reason the experimental animated lock screen failed to start
- Applying a wallpaper no longer turns a mirrored display back into an independent one
- Installed tiles no longer show a leftover Discover preview animation
- Web wallpaper options keep their types and authored order
- Some control panel error messages no longer appear in English when the panel is in Chinese

### 简体中文

WallpaperMachine 1.0 以拖拽安装的磁盘映像发布，并增加了带 Steam 登录的首次运行指南、音乐壁纸可选的“正在播放”支持，以及多项场景渲染修复。

#### 新增

- 下载和应用内更新现在以拖拽安装的磁盘映像提供，首次启动的步骤在系统设置 → 隐私与安全性 → 仍要打开
- 首次运行的欢迎指南用于设置语言和外观、登录 Steam 并提供使用提示，可从设置 → 壁纸库与 Steam 重新打开
- 允许媒体访问后，音乐壁纸可以选择显示 Mac“正在播放”信息中的当前曲目、封面和播放状态
- 音乐壁纸内的播放、暂停、下一首和上一首按钮现在可以控制你正在使用的播放器，并从按钮名称所表示的操作开始
- 可在设置 → 壁纸库与 Steam → 同时下载数中选择同时进行的创意工坊下载数，从 1 到 6
- 设置 → 通用有语言选择器，可选“跟随系统（自动）”、English 和简体中文，并就地切换面板
- 控制面板有 Wallpaper Engine 风格的筛选侧边栏，创意工坊可按类型、年龄分级、分辨率和标签筛选，“发现”还有更多排序方式
- “已安装”可用与“发现”相同的侧边栏条件筛选，并按名称、类型、收藏、文件大小或添加日期排序
- 允许自选图片的壁纸现在会显示你选的图片，而不是自带的配图
- 磁贴会为工作人员认可的项目、收藏，以及已在壁纸库中的壁纸显示角标
- 在 GitHub 上反馈问题现在会打开，并填入该壁纸的详情
- 可在新的品牌应用图标之间选择
- 设置 → 关于会显示最新版本改了什么
- 可选的原生 Metal 渲染器现在可以绘制效果、视频、文字图层、木偶、粒子拖尾和精灵表

#### 改进

- 含有许多大图的场景打开快得多，因为图片只解码一次，并且并行解码
- 新连接的显示器一开始就是启用的，并使用主显示器的壁纸；关掉某一台会在重新连接后仍然记住
- “发现”的下载环会标出当前步骤，例如“连接中”或“登录中”，并在检查和导入文件时显示“收尾中”
- “发现”的预览只下载一次、保存在磁盘上并更早开始播放；调整窗口大小不再重新加载页面
- 你设置的帧率上限现在对响应指针的壁纸同样生效
- 在音乐壁纸上换曲不再重新加载整张壁纸，也不再重新开始其中的视频
- 较重的 3D 壁纸有更多时间来显示第一帧，之后的启动也会更快到达第一帧
- 场景壁纸播放时减少多余的绘制
- 控制面板文案改写成通俗语言，每条消息、菜单和错误现在都译成了简体中文
- 尚未发布任何版本时，检查更新不再报告错误

#### 修复

- 用 Cmd-H 隐藏应用后，或激活一张壁纸后，壁纸不再消失
- 启动时应用会恢复你自己的壁纸，而不是海报或从另一台显示器继承的选择
- 场景视频纹理不再在半秒后卡住，4K 视频场景也不再因为没有第一帧而失败
- 内部渲染比例设置现在对场景壁纸生效
- 壁纸按钮按下后不再一直保持缩小
- 绑定到壁纸音量滑块的声音现在会跟随滑块
- 2D 场景中的摄像机开场会播放；遮罩图层和视差图层留在原位，而不再滑出视野
- 带摄像机图层的 2D 壁纸不再只在一个角落显示一小块
- 在兼容模式渲染器中，模糊图层不再糊成一片灰色
- 为 Wallpaper Engine 编写、以前被静默丢弃的效果现在会出现在对应图层上
- 在原生 Metal 渲染器上，随音频变化的元素会响应声音，而不再变成黑色
- 较重的 3D 场景不再塌成一列，也不再丢失天空、环和大网格
- 鼠标拖尾在靠近屏幕边缘时会跟随光标，而不再从光标飘开
- 视差不再把成组的图层推开，也不再露出它们下面的内容
- 壁纸中由脚本控制的程序坞图标现在会按预期缩放、淡化和打开
- 专辑封面保持作者设定的形状，而不再变成圆形
- 更改设置后，音乐壁纸不再变成空白，不必等到暂停再继续播放才恢复
- 锁屏状态行现在会显示实验性锁定屏幕动态壁纸未能启动的真实原因
- 应用壁纸不再把镜像显示器变回独立显示器
- “已安装”磁贴不再显示残留的“发现”预览动画
- 网页壁纸的选项保持其类型和作者设定的顺序
- 面板为中文时，部分控制面板错误信息不再显示为英文

**Full changelog**: https://github.com/WallpaperMachine/WallpaperMachine/compare/v0.5.0...v1.0.0

## 0.5.0 — 2026-09-18

### English

#### New

- **panel** — Steam sign-in guides, logout wording, filter rail and top bar ([`bda404d`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/bda404d))
- **scene,web** — Static subgraph reuse, web audio/media APIs, user file properties ([`dd01e58`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/dd01e58))
- **quality** — Internal render scale, quality settings, shared video decode ([`48b8df2`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/48b8df2))
- **native video** — Enhance rejectNativeVideo method with admission key and update related structures ([`47b12b1`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/47b12b1))
- **native video** — Implement native video wallpaper support and diagnostics ([`c0461f7`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/c0461f7))
- **presentation** — Enhance wallpaper suspension with per-display control ([`e39f0c4`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/e39f0c4))

Plus 2 documentation, test and tooling commits.

### 简体中文

#### 新增

- **panel** — Steam 登录引导、退出登录文案、筛选栏和顶栏 ([`bda404d`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/bda404d))
- **scene,web** — 静态子图复用、网页音频/媒体 API、用户文件属性 ([`dd01e58`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/dd01e58))
- **quality** — 内部渲染比例、画质设置、共享视频解码 ([`48b8df2`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/48b8df2))
- **native video** — 增强 rejectNativeVideo 方法，为其加入 admission key，并更新相关结构 ([`47b12b1`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/47b12b1))
- **native video** — 实现原生视频壁纸支持与诊断 ([`c0461f7`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/c0461f7))
- **presentation** — 增强壁纸暂停，支持按显示器控制 ([`e39f0c4`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/e39f0c4))

另有 2 个文档、测试和工具相关的提交。

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.4.0...v0.5.0

## 0.4.0 — 2026-09-18

### English

#### New

- **workshop** — Concurrent downloads, tile download rings and grid-sized Discover pages ([`b0eaeed`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/b0eaeed))
- **panel** — Batch deletion, cached thumbnails, resizable layout and display names ([`6dc8c32`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/6dc8c32))

#### Fixed

- **renderer** — Drive vector material timelines and their events ([`511f59d`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/511f59d))

#### Performance

- **playback** — Reduce steady-state rendering and input work ([`084c054`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/084c054))

### 简体中文

#### 新增

- **workshop** — 并发下载、磁贴下载环，以及按网格尺寸分页的“发现”页面 ([`b0eaeed`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/b0eaeed))
- **panel** — 批量删除、缓存的缩略图、可调整大小的布局和显示器名称 ([`6dc8c32`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/6dc8c32))

#### 修复

- **renderer** — 驱动矢量材质的时间线及其事件 ([`511f59d`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/511f59d))

#### 性能

- **playback** — 减少稳态下的渲染和输入工作 ([`084c054`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/084c054))

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.3.2...v0.4.0

## 0.3.2 — 2026-09-17

### English

#### New

- **web** — Host web wallpapers in WKWebView with mouse input ([`42a8fd8`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/42a8fd8))

#### Fixed

- **scene** — Map cursor input through the presented wallpaper ([`3bb8899`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3bb8899))
- **renderer** — Script side-effect writes, puppet animation layers, cursor coverage ([`2385923`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/2385923))

Plus 1 documentation, test and tooling commit.

### 简体中文

#### 新增

- **web** — 在 WKWebView 中承载网页壁纸，并支持鼠标输入 ([`42a8fd8`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/42a8fd8))

#### 修复

- **scene** — 经当前呈现的壁纸映射光标输入 ([`3bb8899`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3bb8899))
- **renderer** — 脚本副作用写入、木偶动画图层、光标覆盖范围 ([`2385923`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/2385923))

另有 1 个文档、测试和工具相关的提交。

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.3.1...v0.3.2

## 0.3.1 — 2026-09-16

### English

#### Fixed

- **updates** — Restore Settings About check-for-updates controls ([`3a653ec`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3a653ec))

#### Other changes

- Update property-script evaluation to persist state across frames ([`169eba6`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/169eba6))
- **workspace** — Reorganize the tree and build a documentation set ([`518ff23`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/518ff23))

Plus 1 documentation, test and tooling commit.

### 简体中文

#### 修复

- **updates** — 恢复设置 → 关于中的检查更新控件 ([`3a653ec`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3a653ec))

#### 其他变更

- 更新属性脚本的求值，使状态在帧与帧之间保持 ([`169eba6`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/169eba6))
- **workspace** — 重组目录树并建立一套文档 ([`518ff23`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/518ff23))

另有 1 个文档、测试和工具相关的提交。

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.3.0...v0.3.1

## 0.3.0 — 2026-09-16

### English

#### New

- **appearance** — Add light theme, system adaptation and customization ([`07ba75e`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/07ba75e))
- **downloads** — Report real transfer speed and byte progress ([`d22b49b`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/d22b49b))

#### Fixed

- **downloads** — Expose NetworkReceiveMeter initializer ([`fca8f87`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/fca8f87))
- **text** — Center each line inside the layer box ([`4cb3819`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/4cb3819))
- **scene** — Leave callback-only property scripts on their base value ([`8a09bd9`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/8a09bd9))
- **scene** — Drive the global camera from the general.zoom animation ([`c0a9641`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/c0a9641))
- **mdl** — Keep the authored MDLS3 skeleton and pivots ([`463b4c4`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/463b4c4))

#### Other changes

- 0.3.0 ([`fadecdb`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/fadecdb))
- Optimize continuous playback resource reuse ([`8f53466`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/8f53466))
- Reduce idle wallpaper background work ([`b03f6c4`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/b03f6c4))

Plus 2 documentation, test and tooling commits.

### 简体中文

#### 新增

- **appearance** — 增加浅色主题、跟随系统以及自定义 ([`07ba75e`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/07ba75e))
- **downloads** — 报告真实的传输速度和字节进度 ([`d22b49b`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/d22b49b))

#### 修复

- **downloads** — 公开 NetworkReceiveMeter 的初始化器 ([`fca8f87`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/fca8f87))
- **text** — 使每一行在图层框内居中 ([`4cb3819`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/4cb3819))
- **scene** — 让仅含回调的属性脚本保持在其基础值上 ([`8a09bd9`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/8a09bd9))
- **scene** — 由 general.zoom 动画驱动全局摄像机 ([`c0a9641`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/c0a9641))
- **mdl** — 保留作者设定的 MDLS3 骨架和枢轴 ([`463b4c4`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/463b4c4))

#### 其他变更

- 0.3.0 ([`fadecdb`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/fadecdb))
- 优化连续播放时的资源复用 ([`8f53466`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/8f53466))
- 减少空闲壁纸的后台工作 ([`b03f6c4`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/b03f6c4))

另有 2 个文档、测试和工具相关的提交。

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.2.1...v0.3.0

## 0.2.1 — 2026-09-16

### English

#### Fixed

- **lockscreen** — Always hand the desktop back to the poster provider ([`9e21b68`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/9e21b68))
- Keep Workshop page turns off the main tab path ([`7525e25`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/7525e25))

#### Other changes

- 0.2.1 ([`7180677`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/7180677))
- Fix presentation suspension and frame timing regressions ([`f56e00d`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/f56e00d))
- Add WallpaperPresentationPolicy to suspend rendering when occluded ([`7db2382`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/7db2382))

Plus 1 documentation, test and tooling commit.

### 简体中文

#### 修复

- **lockscreen** — 始终把桌面交还给海报提供方 ([`9e21b68`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/9e21b68))
- 使创意工坊的翻页不经过主标签路径 ([`7525e25`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/7525e25))

#### 其他变更

- 0.2.1 ([`7180677`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/7180677))
- 修复呈现暂停和帧计时的回归 ([`f56e00d`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/f56e00d))
- 增加 WallpaperPresentationPolicy，在被遮挡时暂停渲染 ([`7db2382`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/7db2382))

另有 1 个文档、测试和工具相关的提交。

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.2.0...v0.2.1

## 0.2.0 — 2026-09-15

### English

#### Other changes

- 0.2.0 ([`ccda129`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/ccda129))
- Replace native SwiftUI panels with the WebKit control panel ([`7b83b4e`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/7b83b4e))

### 简体中文

#### 其他变更

- 0.2.0 ([`ccda129`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/ccda129))
- 用 WebKit 控制面板替换原生 SwiftUI 面板 ([`7b83b4e`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/7b83b4e))

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.1.8...v0.2.0

## 0.1.8 — 2026-09-15

### English

#### Other changes

- Hand the staging claim to SteamCMD and fail closed without it ([`180fc3c`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/180fc3c))
- Require proof nothing is writing before reclaiming staging ([`8ac6f88`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/8ac6f88))
- Reclaim download staging stranded by a crash ([`eeb5e88`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/eeb5e88))
- Pin the Download Details sheet environment with an offscreen test ([`57aa2eb`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/57aa2eb))

### 简体中文

#### 其他变更

- 把暂存认领交给 SteamCMD，没有它时按失败关闭处理 ([`180fc3c`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/180fc3c))
- 在回收暂存区之前，要求证明没有任何写入 ([`8ac6f88`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/8ac6f88))
- 回收因崩溃而滞留的下载暂存区 ([`eeb5e88`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/eeb5e88))
- 用离屏测试固定“下载详情”表单所读取的环境 ([`57aa2eb`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/57aa2eb))

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.1.5...v0.1.8

## 0.1.5 — 2026-09-15

### English

#### Other changes

- Give sheet content the environment it reads ([`3987685`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3987685))

### 简体中文

#### 其他变更

- 向表单内容提供它所读取的环境 ([`3987685`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3987685))

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.1.4...v0.1.5

## 0.1.4 — 2026-09-15

### English

#### Other changes

- Drop the download mark from the private SteamCMD copy ([`15cf07f`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/15cf07f))

### 简体中文

#### 其他变更

- 从私有的 SteamCMD 副本中去掉下载标记 ([`15cf07f`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/15cf07f))

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.1.3...v0.1.4

## 0.1.3 — 2026-09-15

### English

#### Other changes

- Keep the library grid out of the type checker's limit ([`59857dd`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/59857dd))
- Validate SteamCMD the way dyld does and build releases in CI ([`b0bc639`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/b0bc639))

### 简体中文

#### 其他变更

- 让壁纸库网格避开类型检查器的上限 ([`59857dd`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/59857dd))
- 按 dyld 的方式校验 SteamCMD，并在 CI 中构建发布版本 ([`b0bc639`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/b0bc639))

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.1.1...v0.1.3

## 0.1.1 — 2026-09-15

### English

#### Other changes

- Fix one-click SteamCMD install for signed CLI tools and updater links ([`3a4033b`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3a4033b))

### 简体中文

#### 其他变更

- 修复已签名命令行工具和更新器链接的一键 SteamCMD 安装 ([`3a4033b`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3a4033b))

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/compare/v0.1.0...v0.1.1

## 0.1.0 — 2026-09-15

### English

#### Other changes

- Remove unused updater leftovers and ignore local verification artifacts ([`eb72174`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/eb72174))
- Add confirmed GitHub Release updates so installed builds can download and restart-install ([`3338eb8`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3338eb8))
- Add version bump CI triggered by release: commits ([`d882916`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/d882916))
- Improve native wallpaper workflows and SteamCMD installation ([`aa7c22c`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/aa7c22c))
- Integrate native lock-screen wallpapers and harden audio capture lifecycle ([`ecfe88f`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/ecfe88f))
- Document native verification, renderer probes, and desktop tooling ([`311ab7a`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/311ab7a))
- Queue concurrent Workshop downloads and safely adopt completed imports ([`db27a08`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/db27a08))
- Fix renderer compatibility and render-target lifetime regressions ([`e455b6b`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/e455b6b))
- Publish complete project snapshot including completed agent changes ([`1fb3048`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/1fb3048))
- Publish initial source snapshot excluding concurrent agent work ([`9f33787`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/9f33787))

### 简体中文

#### 其他变更

- 移除未使用的更新器残留，并忽略本地验证产物 ([`eb72174`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/eb72174))
- 增加已经确认的 GitHub Release 更新，使已安装的构建可以下载并重启安装 ([`3338eb8`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/3338eb8))
- 增加由 release: 提交触发的版本号提升 CI ([`d882916`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/d882916))
- 改进原生壁纸流程和 SteamCMD 安装 ([`aa7c22c`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/aa7c22c))
- 集成原生锁屏壁纸，并加固音频采集的生命周期 ([`ecfe88f`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/ecfe88f))
- 为原生验证、渲染器探测和桌面工具编写文档 ([`311ab7a`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/311ab7a))
- 为并发的创意工坊下载排队，并安全接纳已完成的导入 ([`db27a08`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/db27a08))
- 修复渲染器兼容性和渲染目标生命周期的回归 ([`e455b6b`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/e455b6b))
- 发布包含已完成代理更改的完整项目快照 ([`1fb3048`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/1fb3048))
- 发布不包含并发代理工作的初始源码快照 ([`9f33787`](https://github.com/bobbyhuang-dev/WallpaperMachine/commit/9f33787))

**Full changelog**: https://github.com/bobbyhuang-dev/WallpaperMachine/commits/v0.1.0
