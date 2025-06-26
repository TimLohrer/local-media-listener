use ::windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager;

#[tokio::main]
async fn main() {
    match get_media_info().await {
        Ok(info) => {
            if !info.is_empty() {
                println!("{}", info);
            } else {
                println!("No media information available.");
            }
        }
        Err(e) => {
            eprintln!("Error retrieving media information: {}", e);
        }
    }
}

async fn get_media_info() -> ::windows::core::Result<String> {
    let manager_future = match GlobalSystemMediaTransportControlsSessionManager::RequestAsync() {
        Ok(fut) => fut,
        Err(_) => return Ok(String::new()),
    };

    let manager = match futures::FutureExt::map(futures::future::ready(manager_future), |fut| fut).await.get() {
        Ok(mgr) => mgr,
        Err(_) => return Ok(String::new()),
    };

    let session = match manager.GetCurrentSession() {
        Ok(ses) => ses,
        Err(_) => return Ok(String::new()),
    };

    let props_future = match session.TryGetMediaPropertiesAsync() {
        Ok(p) => p,
        Err(_) => return Ok(String::new()),
    };

    let props = match futures::FutureExt::map(futures::future::ready(props_future), |fut| fut).await.get() {
        Ok(p) => p,
        Err(_) => return Ok(String::new()),
    };

    let title = props.Title().unwrap_or_default();
    let artist = props.Artist().unwrap_or_default();
    let album = props.AlbumTitle().unwrap_or_default();
    let thumbnail = props.Thumbnail().ok();
    let app = session.SourceAppUserModelId().unwrap_or_default();

    let thumb_url = match thumbnail {
        Some(t) => {
            let stream_future = t.OpenReadAsync().ok();
            let stream = match futures::FutureExt::map(futures::future::ready(stream_future), |fut| fut).await.unwrap().get() {
                Ok(s) => s,
                Err(_) => return Ok(String::new()),
            };
            let buffer_size = 1_048_576; // 1 MB, adjust as needed
            let buffer = ::windows::Storage::Streams::Buffer::Create(buffer_size).unwrap();
            let buffer_future = stream.ReadAsync(&buffer, buffer_size, ::windows::Storage::Streams::InputStreamOptions::None).ok();
            let buffer = match futures::FutureExt::map(futures::future::ready(buffer_future), |fut| fut).await.unwrap().get() {
                Ok(b) => b,
                Err(_) => return Ok(String::new()),
            };
            use ::windows::Storage::Streams::DataReader;
            let data_reader = DataReader::FromBuffer(&buffer).unwrap();
            let length = data_reader.UnconsumedBufferLength().unwrap();
            let mut bytes = vec![0u8; length as usize];
            data_reader.ReadBytes(&mut bytes).unwrap();
            format!("data:image/png;base64,{}", base64::encode(bytes))
        }
        None => String::new(),
    };

    let output = format!("{}|{}|{}|{}|{}", title, artist, album, thumb_url, app);
    Ok(output)
}
