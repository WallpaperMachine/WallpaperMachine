use std::fs;

use crate::{
    BridgeWallpaperKind, WallpaperBridge, api::BridgeBuilder, engine::FakeEngineFacade,
    paths::BridgePaths,
};

#[tokio::test]
async fn filter_hides_disabled_wallpaper_kinds() {
    let bridge = WallpaperBridge::new_for_test();
    bridge
        .inject_wallpaper_for_test("scene", "Scene", BridgeWallpaperKind::ProjectScene)
        .await;
    bridge
        .inject_wallpaper_for_test("video", "Video", BridgeWallpaperKind::Video)
        .await;

    let bundle = bridge
        .set_filter(BridgeWallpaperKind::Video, false)
        .await
        .unwrap();

    let snapshot = bundle.library;
    assert_eq!(snapshot.video_count, 1);
    assert!(snapshot.wallpapers.iter().any(|entry| entry.id == "scene"));
    assert!(!snapshot.wallpapers.iter().any(|entry| entry.id == "video"));

    let snapshot = bridge.library_snapshot().await.unwrap();
    assert!(!snapshot.wallpapers.iter().any(|entry| entry.id == "video"));
}

#[tokio::test]
async fn refresh_preserves_hidden_wallpapers_across_next_snapshot_and_concurrent_snapshot() {
    // The bridge's own paths, not a process-wide HOME: every other test scans
    // a library too, and a shared HOME hands them this one mid-run.
    let home = tempfile::tempdir().unwrap();
    let workshop = BridgePaths::for_home(home.path()).steam_workshop_root();
    write_project(&workshop, "scene", r#"{"type":"scene","title":"Scene"}"#);
    write_project(&workshop, "video", r#"{"type":"video","title":"Video"}"#);
    let bridge_for_home = || {
        BridgeBuilder::new(FakeEngineFacade::default())
            .with_paths(BridgePaths::for_home(home.path()))
            .build()
            .expect("tokio runtime and config load for wallpaper bridge")
    };

    let bridge = bridge_for_home();
    bridge
        .set_filter(BridgeWallpaperKind::Video, false)
        .await
        .unwrap();
    let refreshed = bridge.refresh_library().await.unwrap().library;
    assert!(refreshed.wallpapers.iter().any(|entry| entry.id == "scene"));
    assert!(!refreshed.wallpapers.iter().any(|entry| entry.id == "video"));

    let snapshot = bridge
        .set_filter(BridgeWallpaperKind::Video, true)
        .await
        .unwrap()
        .library;
    assert!(snapshot.wallpapers.iter().any(|entry| entry.id == "video"));

    let concurrent_bridge = bridge_for_home();
    concurrent_bridge
        .set_filter(BridgeWallpaperKind::Video, false)
        .await
        .unwrap();

    let (refresh, _snapshot) = tokio::join!(
        concurrent_bridge.refresh_library(),
        concurrent_bridge.library_snapshot()
    );
    refresh.unwrap();

    let snapshot = concurrent_bridge
        .set_filter(BridgeWallpaperKind::Video, true)
        .await
        .unwrap()
        .library;
    assert!(snapshot.wallpapers.iter().any(|entry| entry.id == "video"));
}

fn write_project(workshop: &std::path::Path, id: &str, project_json: &str) {
    let dir = workshop.join(id);
    fs::create_dir_all(&dir).unwrap();
    fs::write(dir.join("project.json"), project_json).unwrap();
}
