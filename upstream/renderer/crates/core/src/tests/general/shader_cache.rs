use std::fs;

use crate::{
    project::SceneDesc,
    render::{ShaderCacheDecision, ShaderCacheInputs},
};

#[test]
fn unpacked_scene_cache_tracks_entries_and_resources_without_tracking_itself() {
    for entry in ["scene.json", "scenes/custom.json"] {
        let root = tempfile::tempdir().unwrap();
        let entry_path = root.path().join(entry);
        fs::create_dir_all(entry_path.parent().unwrap()).unwrap();
        fs::write(&entry_path, r#"{"objects":[]}"#).unwrap();
        let project = root.path().join("project.json");
        fs::write(&project, serde_json::json!({"type":"scene","file":entry}).to_string()).unwrap();
        let shaders = root.path().join("shaders");
        fs::create_dir_all(&shaders).unwrap();
        let shader = shaders.join("common.glsl");
        fs::write(&shader, "float value = 1.0;\n").unwrap();
        let descriptor = crate::project::SceneDesc::builder(
            crate::DisplayDesc::new(1, 0, 0, 100, 100, 1.0), project.to_string_lossy())
            .shader_cache_path(root.path().join("cache").to_string_lossy()).build().unwrap();
        let cache = std::path::PathBuf::from(descriptor.shader_cache_path().unwrap().unwrap());
        let artifact = cache.join("compiled-shader");
        fs::write(&artifact, "cached").unwrap();
        assert_eq!(descriptor.shader_cache_path().unwrap().as_deref(), cache.to_str());
        assert!(artifact.is_file(), "cache outputs must not invalidate source fingerprints");
        fs::write(&shader, "float value = 22.0;\n").unwrap();
        descriptor.shader_cache_path().unwrap();
        assert!(!artifact.exists(), "changed physical shader resources invalidate the cache");
        fs::write(&artifact, "cached").unwrap();
        fs::write(&entry_path, r#"{"objects":[],"general":{}}"#).unwrap();
        descriptor.shader_cache_path().unwrap();
        assert!(!artifact.exists(), "the custom entry participates in freshness");
    }
}

#[test]
pub fn case_shader_cache_prepare() {
    let root = tempfile::tempdir().expect("tempdir should exist");
    let project_path = root.path().join("project.json");
    let pkg_path = root.path().join("scene.pkg");
    fs::write(&project_path, "{}").expect("project should write");
    fs::write(&pkg_path, "pkg").expect("pkg should write");

    let inputs = ShaderCacheInputs::builder("demo-scene", root.path().join("cache"))
        .project_json_path(&project_path)
        .scene_pkg_path(&pkg_path)
        .build()
        .expect("inputs should build");

    let cold = ShaderCacheDecision::prepare(&inputs).expect("cold cache should prepare");
    assert!(cold.purged_cache());

    let warm = ShaderCacheDecision::prepare(&inputs).expect("warm cache should prepare");
    assert!(!warm.purged_cache());
}

#[test]
pub fn case_shader_cache_purges_when_property_overrides_change() {
    let root = tempfile::tempdir().expect("tempdir should exist");
    let project_path = root.path().join("project.json");
    let pkg_path = root.path().join("scene.pkg");
    fs::write(&project_path, "{}").expect("project should write");
    fs::write(&pkg_path, "pkg").expect("pkg should write");

    let first = ShaderCacheInputs::builder("demo-scene", root.path().join("cache"))
        .project_json_path(&project_path)
        .scene_pkg_path(&pkg_path)
        .property_override_json(Some(r#"{"color":"red"}"#))
        .build()
        .expect("inputs should build");
    let second = ShaderCacheInputs::builder("demo-scene", root.path().join("cache"))
        .project_json_path(&project_path)
        .scene_pkg_path(&pkg_path)
        .property_override_json(Some(r#"{"color":"blue"}"#))
        .build()
        .expect("inputs should build");

    let cold = ShaderCacheDecision::prepare(&first).expect("cold cache should prepare");
    assert!(cold.purged_cache());

    let changed = ShaderCacheDecision::prepare(&second).expect("changed cache should prepare");
    assert!(changed.purged_cache());

    let warm = ShaderCacheDecision::prepare(&second).expect("warm cache should prepare");
    assert!(!warm.purged_cache());
}

#[test]
pub fn case_shader_cache_rejects_scene_id_path_escape() {
    let root = tempfile::tempdir().expect("tempdir should exist");
    let project_path = root.path().join("project.json");
    let pkg_path = root.path().join("scene.pkg");
    let cache_root = root.path().join("cache");
    let victim_path = root.path().join("victim").join("keep.txt");
    fs::create_dir_all(victim_path.parent().unwrap()).expect("victim dir should write");
    fs::write(&victim_path, "do not delete").expect("victim should write");
    fs::write(&project_path, "{}").expect("project should write");
    fs::write(&pkg_path, "pkg").expect("pkg should write");

    let error = ShaderCacheInputs::builder("../victim", &cache_root)
        .project_json_path(&project_path)
        .scene_pkg_path(&pkg_path)
        .force_refresh(true)
        .build()
        .expect_err("path traversal scene id should fail");

    assert!(matches!(error, crate::EngineError::InvalidInput(_)));
    assert!(victim_path.exists());

    for invalid in ["/absolute", "nested/path", "nested\\path", "."] {
        assert!(
            ShaderCacheInputs::builder(invalid, &cache_root)
                .project_json_path(&project_path)
                .scene_pkg_path(&pkg_path)
                .build()
                .is_err()
        );
    }
}

#[test]
pub fn case_shader_cache_ignores_non_scene_projects() {
    let root = tempfile::tempdir().expect("tempdir should exist");
    let project_path = root.path().join("project.json");
    fs::write(
        &project_path,
        r#"{"type":"video","file":"video.mp4","workshopid":"video-demo"}"#,
    )
    .expect("project should write");

    let scene = SceneDesc::builder(
        crate::DisplayDesc::new(1, 0, 0, 1920, 1080, 1.0),
        project_path.to_string_lossy(),
    )
    .assets_path(root.path().join("assets").to_string_lossy())
    .shader_cache_path(root.path().join("cache").to_string_lossy())
    .build()
    .expect("scene desc should build");

    let cache_path = scene
        .shader_cache_path()
        .expect("non-scene projects should not require scene.pkg metadata");

    assert_eq!(cache_path, None);
}
