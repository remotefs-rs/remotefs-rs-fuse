mod cli;

use remotefs_fuse::{Driver, Mount, MountOption};

fn main() -> anyhow::Result<()> {
    let args = argh::from_env::<cli::CliArgs>();
    args.init_logger()?;
    let volume = args.volume.clone();
    let mount_path = args.to.clone();
    let remote = args.remote();

    let driver = Driver::new(remote);

    log::info!("Mounting remote fs at {}", mount_path.display());

    // create the mount point if it does not exist
    if !mount_path.exists() {
        log::info!("creating mount point at {}", mount_path.display());
        std::fs::create_dir_all(&mount_path)?;
    }

    // Mount the remote file system
    let mut mount = Mount::mount(
        driver,
        &mount_path,
        &[
            MountOption::AllowRoot,
            MountOption::RW,
            MountOption::Exec,
            MountOption::Sync,
            MountOption::FSName(volume),
        ],
    )?;

    let mut umount = mount.unmounter();

    // setup signal handler
    ctrlc::set_handler(move || {
        log::info!("Received SIGINT, unmounting filesystem");
        umount.umount().expect("Failed to unmount");
    })?;

    log::info!("Running filesystem event loop");
    mount.run()?;

    Ok(())
}
