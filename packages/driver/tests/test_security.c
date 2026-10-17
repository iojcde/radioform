#include "../include/RFSharedAudio.h"
#include "../include/RFSecureIPC.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>

static void test_ring(void) {
    for (uint32_t format = RF_FORMAT_FLOAT32; format <= RF_FORMAT_INT32; ++format) {
        size_t size = rf_shared_audio_size(4800, 2, rf_bytes_per_sample(format));
        RFSharedAudio* mem = calloc(1, size);
        assert(mem);
        rf_shared_audio_init(mem, 48000, 2, format, 100);
        RFAudioLayout layout;
        assert(rf_audio_layout_snapshot(mem, size, &layout));
        assert(!rf_audio_layout_snapshot(mem, sizeof(RFSharedAudio) - 1, &layout));
        assert(!rf_audio_layout_snapshot(mem, size - 1, &layout));
        // Reproduce the original attack after retaining the valid private layout.
        mem->bytes_per_frame = (uint32_t)size;
        mem->channels = UINT32_MAX;
        mem->ring_capacity_frames = 0;
        mem->format = UINT32_MAX;
        RFAudioLayout rejected;
        assert(!rf_audio_layout_snapshot(mem, size, &rejected));
        float input[] = {0.25f, -0.25f, 0.5f, -0.5f};
        float output[4] = {0};
        assert(rf_ring_write(mem, &layout, input, 2, 4) == 2);
        assert(rf_ring_read(mem, &layout, output, 2, 4) == 2);
        for (size_t i = 0; i < 4; ++i) assert(fabsf(output[i] - input[i]) < 0.0001f);
        assert(rf_ring_write(mem, &layout, input, 3, 4) == 0);
        assert(rf_ring_read(mem, &layout, output, 3, 4) == 0);
        atomic_store(&mem->write_index, 1);
        atomic_store(&mem->read_index, 2);
        assert(rf_ring_write(mem, &layout, input, 2, 4) == 0);
        assert(rf_ring_read(mem, &layout, output, 2, 4) == 0);
        atomic_store(&mem->write_index, UINT64_MAX);
        atomic_store(&mem->read_index, UINT64_MAX);
        assert(rf_ring_write(mem, &layout, input, 2, 4) == 0);
        // Exercise wraparound and inputs larger than the ring.
        atomic_store(&mem->write_index, 4799);
        atomic_store(&mem->read_index, 4799);
        assert(rf_ring_write(mem, &layout, input, 2, 4) == 2);
        assert(rf_ring_read(mem, &layout, output, 2, 4) == 2);
        float* large = calloc(4801 * 2, sizeof(float));
        assert(large);
        assert(rf_ring_write(mem, &layout, large, 4801, 4801 * 2) == 4801);
        assert(atomic_load(&mem->write_index) - atomic_load(&mem->read_index) == 4800);
        free(large);
        atomic_store(&mem->write_index, 0);
        atomic_store(&mem->read_index, 0);
        float extremes[] = {1, -1, 2, -2, NAN, INFINITY, -INFINITY, 0};
        float checked[8];
        assert(rf_ring_write(mem, &layout, extremes, 4, 8) == 4);
        assert(rf_ring_read(mem, &layout, checked, 4, 8) == 4);
        assert(checked[0] > .999f && checked[1] < -.999f);
        for (size_t i = 0; i < 8; ++i) assert(isfinite(checked[i]));
        for (size_t i = 4; i < 8; ++i) assert(checked[i] == 0);
        // A peer can bypass the writer and put invalid floats directly in IPC.
        if (format == RF_FORMAT_FLOAT32 || format == RF_FORMAT_FLOAT64) {
            atomic_store(&mem->write_index, 1);
            atomic_store(&mem->read_index, 0);
            if (format == RF_FORMAT_FLOAT32) {
                ((float*)mem->audio_data)[0] = NAN;
                ((float*)mem->audio_data)[1] = INFINITY;
            } else {
                ((double*)mem->audio_data)[0] = NAN;
                ((double*)mem->audio_data)[1] = INFINITY;
            }
            assert(rf_ring_read(mem, &layout, checked, 1, 8) == 1);
            assert(checked[0] == 0 && checked[1] == 0);
        }
        if (format >= RF_FORMAT_INT16) {
            assert(checked[2] > .999f && checked[2] <= 1);
            assert(checked[3] < -.999f && checked[3] >= -1);
        }
        free(mem);
    }
}

static void test_files(void) {
    char path[] = "/private/tmp/radioform-security-test.XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);
    assert(rf_ipc_set_permissions(fd, true) == 0);
    struct stat st;
    assert(fstat(fd, &st) == 0 && (st.st_mode & 0777) == 0600);
    // Verify that the ACL contains exactly the intended service principal.
    acl_t acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
    assert(acl);
    acl_entry_t entry;
    assert(acl_get_entry(acl, ACL_FIRST_ENTRY, &entry) == 0);
    uuid_t expected;
    assert(mbr_uid_to_uuid(getpwnam("_coreaudiod")->pw_uid, expected) == 0);
    void* qualifier = acl_get_qualifier(entry);
    assert(qualifier && memcmp(qualifier, expected, sizeof(expected)) == 0);
    acl_free(qualifier);
    acl_permset_t perms;
    assert(acl_get_permset(entry, &perms) == 0);
    assert(acl_get_perm_np(perms, ACL_READ_DATA) == 1);
    assert(acl_get_perm_np(perms, ACL_WRITE_DATA) == 1);
    assert(acl_get_entry(acl, ACL_NEXT_ENTRY, &entry) != 0);
    acl_free(acl);
    assert(rf_ipc_set_permissions(fd, false) == 0);
    acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
    assert(acl && acl_get_entry(acl, ACL_FIRST_ENTRY, &entry) == 0);
    assert(acl_get_permset(entry, &perms) == 0);
    assert(acl_get_perm_np(perms, ACL_READ_DATA) == 1);
    assert(acl_get_perm_np(perms, ACL_WRITE_DATA) == 0);
    acl_free(acl);
    // A planted file or symlink must never be opened for creation/truncation.
    assert(open(path, O_CREAT | O_EXCL | O_NOFOLLOW | O_RDWR, 0600) == -1);
    char link_path[256];
    snprintf(link_path, sizeof(link_path), "%s.link", path);
    assert(symlink(path, link_path) == 0);
    assert(rf_ipc_open(link_path, O_RDWR, 0, 4096, &st) == -1);
    assert(rf_ipc_open(path, O_RDONLY, 1, 4096, &st) == -1);
    struct stat console;
    assert(stat("/dev/console", &console) == 0);
    if (console.st_uid == getuid() && getuid() != 0) {
        int reader = rf_ipc_open(path, O_RDONLY, 0, 4096, &st);
        assert(reader >= 0);
        close(reader);
    }
    assert(fchmod(fd, 0666) == 0);
    assert(rf_ipc_open(path, O_RDONLY, 0, 4096, &st) == -1);
    unlink(link_path);
    close(fd);
    unlink(path);
}

int main(void) {
    test_ring();
    test_files();
    puts("Audio bounds, metadata corruption, private ACLs and symlink checks passed");
}
