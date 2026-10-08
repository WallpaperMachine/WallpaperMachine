use crate::{BridgePropertyValue, WallpaperBridge};

#[tokio::test]
async fn preview_reads_the_draft_without_selecting_applying_or_consuming_it() {
    let bridge = WallpaperBridge::new_for_test();
    bridge.inject_scene_project_for_test("preview", "Preview", r#"{
        "type":"scene", "file":"scene.json", "title":"Preview",
        "general":{"properties":{"size":{"type":"slider","value":10,"min":0,"max":100}}}
    }"#).await;
    bridge.select_wallpaper("preview".into()).await.unwrap();
    bridge.edit_property("preview".into(), "size".into(), BridgePropertyValue::Number { value: 25.0 }).await.unwrap();
    let before = bridge.all_snapshots().await.unwrap();
    let preview = bridge.wallpaper_preview("preview".into(), "primary".into()).await.unwrap();
    let properties: serde_json::Value = serde_json::from_str(&preview.properties_json).unwrap();
    assert_eq!(properties["size"].as_f64(), Some(25.0));
    assert!(preview.fps <= 30 && preview.fps > 0);
    assert_eq!(bridge.all_snapshots().await.unwrap(), before);
    assert!(bridge.wallpaper_options_snapshot("preview".into()).await.unwrap().dirty);
    assert!(bridge.app_snapshot().await.unwrap().active_wallpaper_ids.is_empty());
}

#[tokio::test]
async fn web_preview_keeps_combo_json_types_and_can_preview_an_unselected_project() {
    let bridge = WallpaperBridge::new_for_test();
    bridge.inject_scene_project_for_test("web-preview", "Web", r#"{
        "type":"web", "file":"index.html", "title":"Web",
        "general":{"properties":{
            "number":{"type":"combo","value":2,"options":[{"label":"Two","value":2}]},
            "flag":{"type":"bool","value":true},
            "label":{"type":"text","text":"Read me"}
        }}
    }"#).await;
    let before = bridge.app_snapshot().await.unwrap();
    let preview = bridge.wallpaper_preview("web-preview".into(), "primary".into()).await.unwrap();
    let properties: serde_json::Value = serde_json::from_str(&preview.properties_json).unwrap();
    assert_eq!(properties["number"]["value"], 2);
    assert_eq!(properties["flag"]["value"], true);
    assert!(properties.get("label").is_none());
    assert_eq!(preview.entry_file, "index.html");
    assert_eq!(bridge.app_snapshot().await.unwrap(), before);
}

#[tokio::test]
async fn preview_refuses_unknown_and_escaping_identifiers() {
    let bridge = WallpaperBridge::new_for_test();
    for id in ["missing", "../outside", "/absolute", ""] {
        assert!(bridge.wallpaper_preview(id.into(), "primary".into()).await.is_err());
    }
}
