use image::codecs::png::PngEncoder;
use image::{ColorType, GenericImageView, ImageEncoder, ImageReader};
use kuma_domain::WorkspaceError;
use std::io::Cursor;

const MAX_SIDE: u32 = 512;

pub fn encode_avatar_png(bytes: &[u8]) -> Result<Vec<u8>, WorkspaceError> {
    let reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| WorkspaceError::ImageInvalid)?;
    let img = reader.decode().map_err(|_| WorkspaceError::ImageInvalid)?;
    let (w, h) = img.dimensions();
    let resized = if w > MAX_SIDE || h > MAX_SIDE {
        img.thumbnail(MAX_SIDE, MAX_SIDE)
    } else {
        img
    };
    let rgba = resized.to_rgba8();
    let mut out = Vec::new();
    PngEncoder::new(&mut out)
        .write_image(rgba.as_raw(), rgba.width(), rgba.height(), ColorType::Rgba8.into())
        .map_err(|_| WorkspaceError::ImageInvalid)?;
    Ok(out)
}
