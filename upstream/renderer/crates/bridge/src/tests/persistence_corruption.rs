use std::fs;

use crate::config::ConfigStore;

#[test]
fn corrupted_config_is_backed_up_and_defaults_are_loaded() {
    let root = tempfile::tempdir().unwrap();
    fs::create_dir_all(root.path()).unwrap();
    fs::write(root.path().join("config.toml"), b"not = [valid").unwrap();

    let load = ConfigStore::open(root.path().to_path_buf()).load().unwrap();

    assert!(load.config.monitors.is_empty());
    let backups = fs::read_dir(root.path())
        .unwrap()
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("config.toml.corrupted-")
        })
        .count();
    assert_eq!(backups, 1);
}

#[test]
fn backup_validation_rejects_corrupt_and_future_renderer_configurations() {
    use crate::{BridgeErrorKind, validate_backup_renderer_configuration};
    use std::collections::HashMap;

    for raw in ["not = [valid", "schema_version = 2\n"] {
        let error = validate_backup_renderer_configuration(Some(raw.into()), HashMap::new())
            .expect_err("an imported config must fail before replacing current settings");
        assert_eq!(error.kind(), BridgeErrorKind::Config);
    }
    for raw in ["{ invalid", r#"{"schema_version":2,"workshop_id":"300","type":"web"}"#] {
        let error = validate_backup_renderer_configuration(
            None, HashMap::from([("wallpapers/300.json".into(), raw.into())]),
        ).expect_err("invalid wallpaper settings must not be published");
        assert_eq!(error.kind(), BridgeErrorKind::Config);
    }
}
