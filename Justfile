# Every workspace feature except `fusibile/smb-vendored`, which compiles Samba
# from source and turns a two-minute check into an hour-long one. Package-qualified
# because this is a virtual workspace.
all_features := "fusibile/aws-s3,fusibile/ftp,fusibile/gcs,fusibile/kube,fusibile/libfuse,fusibile/smb,fusibile/ssh,fusibile/webdav,remotefs-fuse/integration-tests"

import "./just/build.just"
import "./just/changelog.just"
import "./just/code_check.just"
import "./just/publish.just"
import "./just/run.just"
import "./just/test.just"

# List every available command.
default:
    @just --list
