use anyhow::{Context, Result};

/// Returns true when the connected peer UID equals this process UID (spec 10 §2.3).
pub fn peer_uid_matches_daemon(stream_fd: std::os::unix::io::RawFd) -> Result<bool> {
    let peer = peer_uid(stream_fd).context("read peer credentials")?;
    let self_uid = unsafe { libc::getuid() };
    Ok(peer == self_uid)
}

fn peer_uid(stream_fd: std::os::unix::io::RawFd) -> Result<u32> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let mut uid: libc::uid_t = 0;
        let mut gid: libc::gid_t = 0;
        let rc = unsafe { libc::getpeereid(stream_fd, &mut uid, &mut gid) };
        if rc != 0 {
            anyhow::bail!("getpeereid failed: {}", std::io::Error::last_os_error());
        }
        Ok(uid)
    }

    #[cfg(target_os = "linux")]
    {
        use std::mem::MaybeUninit;
        let mut cred = MaybeUninit::<libc::ucred>::uninit();
        let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
        let rc = unsafe {
            libc::getsockopt(
                stream_fd,
                libc::SOL_SOCKET,
                libc::SO_PEERCRED,
                cred.as_mut_ptr().cast(),
                &mut len,
            )
        };
        if rc != 0 {
            anyhow::bail!("SO_PEERCRED failed: {}", std::io::Error::last_os_error());
        }
        let cred = unsafe { cred.assume_init() };
        Ok(cred.uid)
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "linux")))]
    {
        let _ = stream_fd;
        Ok(unsafe { libc::getuid() })
    }
}
