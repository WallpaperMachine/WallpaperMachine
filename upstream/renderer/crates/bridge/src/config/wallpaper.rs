use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use wallpaper_core::project::ScalingMode;

use super::app::SerializedSelector;
use crate::project::PropertyValue;

pub const SCHEMA_VERSION: u32 = 1;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct WallpaperConfig {
    #[serde(default = "default_schema_version")]
    pub schema_version: u32,
    #[serde(default)]
    pub workshop_id: String,
    #[serde(default, rename = "type")]
    pub r#type: String,
    #[serde(default)]
    pub audio: AudioCfg,
    /// The user's consent for this wallpaper to read system media state.
    ///
    /// Off by default, and deliberately so: on current macOS the only system
    /// now-playing source needs a private entitlement this application does
    /// not hold, so turning it on may find nothing. Opting in must be a
    /// decision, not something a wallpaper inherits.
    #[serde(default)]
    pub media_integration_enabled: bool,
    #[serde(default)]
    pub monitors: Vec<MonitorRender>,
    #[serde(default)]
    pub property_overrides: BTreeMap<String, Value>,
}

impl Default for WallpaperConfig {
    fn default() -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            workshop_id: String::new(),
            r#type: String::new(),
            audio: AudioCfg::default(),
            media_integration_enabled: false,
            monitors: Vec::new(),
            property_overrides: BTreeMap::new(),
        }
    }
}

impl WallpaperConfig {
    #[must_use]
    pub fn new_for(workshop_id: impl Into<String>, type_str: impl Into<String>) -> Self {
        Self {
            workshop_id: workshop_id.into(),
            r#type: type_str.into(),
            ..Self::default()
        }
    }

    #[must_use]
    pub fn override_json(&self, id: &str) -> Option<&Value> {
        self.property_overrides.get(id)
    }

    pub fn override_value(&self, id: &str) -> Option<PropertyValue> {
        self.override_json(id).map(PropertyValue::from_json)
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AudioCfg {
    #[serde(default = "default_audio_volume")]
    pub volume: f32,
    #[serde(default = "default_audio_response_enabled")]
    pub response_enabled: bool,
    #[serde(default)]
    pub muted: bool,
}

impl Default for AudioCfg {
    fn default() -> Self {
        Self {
            volume: default_audio_volume(),
            response_enabled: default_audio_response_enabled(),
            muted: false,
        }
    }
}

/// Per-display render overrides for one wallpaper.
///
/// `frame_rate` absent means follow that display's native refresh. Older
/// files stored a hard-coded `fps` of 60 even when nobody had chosen a rate;
/// that value is not a choice and loads as absent. A file this build writes
/// never carries `fps`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(from = "MonitorRenderRaw")]
pub struct MonitorRender {
    #[serde(default)]
    pub selector: SerializedSelector,
    #[serde(default = "default_scaling_mode")]
    pub scaling_mode: String,
    #[serde(default = "default_scaling_factor")]
    pub scaling_factor: f64,
    /// `None` follows the display's native refresh. A number is an explicit
    /// cap below that refresh and is omitted when absent.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frame_rate: Option<u32>,
}

#[derive(Deserialize)]
struct MonitorRenderRaw {
    #[serde(default)]
    selector: SerializedSelector,
    #[serde(default = "default_scaling_mode")]
    scaling_mode: String,
    #[serde(default = "default_scaling_factor")]
    scaling_factor: f64,
    /// Outer `Some` means the key was present, so it wins over legacy `fps`
    /// even when the value is null.
    #[serde(default, deserialize_with = "super::deserialize_present")]
    frame_rate: Option<Option<u32>>,
    #[serde(default)]
    fps: Option<u32>,
}

impl From<MonitorRenderRaw> for MonitorRender {
    fn from(raw: MonitorRenderRaw) -> Self {
        Self {
            selector: raw.selector,
            scaling_mode: raw.scaling_mode,
            scaling_factor: raw.scaling_factor,
            frame_rate: super::frame_rate_from_legacy(raw.frame_rate, raw.fps),
        }
    }
}

impl Default for MonitorRender {
    fn default() -> Self {
        Self {
            selector: SerializedSelector::default(),
            scaling_mode: default_scaling_mode(),
            scaling_factor: default_scaling_factor(),
            frame_rate: None,
        }
    }
}

impl MonitorRender {
    #[must_use]
    pub fn parse_scaling_mode(&self) -> ScalingMode {
        match self.scaling_mode.to_ascii_lowercase().as_str() {
            "none" => ScalingMode::None,
            "stretch" => ScalingMode::Stretch,
            "fill" => ScalingMode::Fill,
            "fit" => ScalingMode::Fit,
            _ => ScalingMode::default(),
        }
    }

    /// The rate this display should run at: the saved cap, or the display's
    /// own refresh when the user has not chosen one.
    #[must_use]
    pub fn fps_on(&self, refresh_hz: u32) -> u32 {
        super::resolve_frame_rate(self.frame_rate, refresh_hz)
    }
}

fn default_schema_version() -> u32 {
    SCHEMA_VERSION
}

fn default_audio_volume() -> f32 {
    1.0
}

fn default_audio_response_enabled() -> bool {
    true
}

fn default_scaling_mode() -> String {
    ScalingMode::default().to_string()
}

fn default_scaling_factor() -> f64 {
    1.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::app::MonitorSettingsCfg;

    #[test]
    fn scaling_defaults_to_fill_and_preserves_saved_choices() {
        assert_eq!(
            MonitorRender::default().parse_scaling_mode(),
            ScalingMode::Fill
        );
        assert_eq!(
            MonitorSettingsCfg::default().parse_scaling_mode(),
            ScalingMode::Fill
        );

        for (json, expected) in [
            (r#"{}"#, ScalingMode::Fill),
            (r#"{"scaling_mode":"fit"}"#, ScalingMode::Fit),
            (r#"{"scaling_mode":"fill"}"#, ScalingMode::Fill),
            (r#"{"scaling_mode":"stretch"}"#, ScalingMode::Stretch),
            (r#"{"scaling_mode":"none"}"#, ScalingMode::None),
            (r#"{"scaling_mode":"unknown"}"#, ScalingMode::Fill),
        ] {
            let wallpaper: MonitorRender = serde_json::from_str(json).unwrap();
            // Display settings flatten their selector, so include its required tag.
            let mut display_json = serde_json::to_value(SerializedSelector::default()).unwrap();
            let fields: serde_json::Map<String, Value> = serde_json::from_str(json).unwrap();
            display_json.as_object_mut().unwrap().extend(fields);
            let display: MonitorSettingsCfg = serde_json::from_value(display_json).unwrap();
            assert_eq!(wallpaper.parse_scaling_mode(), expected);
            assert_eq!(display.parse_scaling_mode(), expected);
        }
    }

    #[test]
    fn legacy_fps_follows_the_display_unless_it_was_an_explicit_cap() {
        let untouched: MonitorRender = serde_json::from_str(r#"{"fps":60}"#).unwrap();
        assert_eq!(untouched.frame_rate, None);
        let missing: MonitorRender = serde_json::from_str("{}").unwrap();
        assert_eq!(missing.frame_rate, None);

        let capped: MonitorRender = serde_json::from_str(r#"{"fps":30}"#).unwrap();
        assert_eq!(capped.frame_rate, Some(30));
        let zero: MonitorRender = serde_json::from_str(r#"{"fps":0}"#).unwrap();
        assert_eq!(zero.frame_rate, Some(1));

        let newer_wins: MonitorRender =
            serde_json::from_str(r#"{"frame_rate":24,"fps":30}"#).unwrap();
        assert_eq!(newer_wins.frame_rate, Some(24));
        let explicit_native_wins: MonitorRender =
            serde_json::from_str(r#"{"frame_rate":null,"fps":30}"#).unwrap();
        assert_eq!(explicit_native_wins.frame_rate, None);

        let saved = serde_json::to_value(MonitorRender::default()).unwrap();
        assert!(saved.get("fps").is_none(), "{saved}");
        assert!(saved.get("frame_rate").is_none(), "{saved}");
        let written = serde_json::to_value(MonitorRender {
            frame_rate: Some(30),
            ..MonitorRender::default()
        })
        .unwrap();
        assert!(written.get("fps").is_none(), "{written}");
        assert_eq!(written["frame_rate"], 30);

        assert_eq!(MonitorRender::default().fps_on(120), 60, "the default stops at 60");
        assert_eq!(MonitorRender::default().fps_on(60), 60);
        assert_eq!(MonitorRender::default().fps_on(48), 48, "below 60 the default follows the display");
        assert_eq!(MonitorRender::default().fps_on(0), 1);
        assert_eq!(capped.fps_on(120), 30);
        assert_eq!(capped.fps_on(24), 24);
    }
}
