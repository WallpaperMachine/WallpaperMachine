mod activation;
mod facade;

pub use activation::{
    ActivationInputs, NativeVideoRejection, NativeVideoRejections, RenderBackendSurvey,
    VideoBackendRouting, WallpaperAssignmentExt,
};
#[cfg(test)]
pub(crate) use facade::apply_audio_capture_demand;
#[cfg(test)]
pub use facade::FakeEngineFacade;
pub use facade::{AudioCaptureDemand, EngineFacade, RealEngineFacade, RendererVideoPipelineState, SceneRuntimeReport};
