#ifndef RF_SECURE_IPC_H
#define RF_SECURE_IPC_H

#include <stdbool.h>
#include <sys/acl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <pwd.h>
#include <membership.h>
#include <errno.h>
#include <stdlib.h>

// Keep the files private to the host user and the CoreAudio service account.
// No group or other access, including during creation. Fail closed if the
// service account or its ACL cannot be configured.
static inline int rf_ipc_set_permissions(int fd, bool writable_by_driver) {
    struct passwd* service = getpwnam("_coreaudiod");
    uuid_t service_id;
    if (!service || mbr_uid_to_uuid(service->pw_uid, service_id) != 0) return -1;
    acl_t acl = acl_init(1);
    if (!acl) return -1;
    acl_entry_t entry;
    acl_permset_t perms;
    int result = -1;
    if (acl_create_entry(&acl, &entry) == 0 &&
        acl_set_tag_type(entry, ACL_EXTENDED_ALLOW) == 0 &&
        acl_set_qualifier(entry, service_id) == 0 &&
        acl_get_permset(entry, &perms) == 0 &&
        acl_add_perm(perms, ACL_READ_DATA) == 0 &&
        (!writable_by_driver || acl_add_perm(perms, ACL_WRITE_DATA) == 0) &&
        acl_set_permset(entry, perms) == 0 &&
        fchmod(fd, 0600) == 0) {
        result = acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED);
    }
    acl_free(acl);
    return result;
}

// Open first, then inspect that exact inode. O_NONBLOCK also rejects a planted
// FIFO without hanging CoreAudio. Only the active console user's files count.
static inline int rf_ipc_open(const char* path, int flags, size_t min_size,
                              size_t max_size, struct stat* info) {
    int fd = open(path, flags | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat console;
    if (fstat(fd, info) != 0 || stat("/dev/console", &console) != 0 ||
        !S_ISREG(info->st_mode) || info->st_nlink != 1 ||
        info->st_uid != console.st_uid || console.st_uid == 0 ||
        (info->st_mode & 0077) != 0 || info->st_size < 0 ||
        (size_t)info->st_size < min_size || (size_t)info->st_size > max_size) {
        close(fd);
        errno = EPERM;
        return -1;
    }
    return fd;
}

#endif
