# special bats function
setup() {
    load 'bats-support/load'
	load 'bats-assert/load'
	load 'bats-file/load'

    # create temp directory
    # https://github.com/ztombol/bats-file#temp_make
    WORKDIR=$(temp_make)
    TESTDIR="$WORKDIR/test"
    cd "$WORKDIR"

    # https://www.cyberciti.biz/faq/howto-create-lage-files-with-dd-command/
    # https://ubuntuhak.blogspot.com/2012/10/how-to-create-format-and-mount-img-files.html
    
    # create disk image for testing
    # NOTE: keep disk size small to make tests run faster
    dd if=/dev/zero of=test.img bs=1K count=2048 conv=sparse status=none
    # create partition in the disk image; try to be more exact
    mkfs -t ext4 test.img 1060 >/dev/null 2>&1
    # mount the disk image
    mkdir -p test
    sudo mount -o loop,rw,sync test.img "$TESTDIR"
    # allow writing to the mounted image
    sudo chown $(id -u):$(id -g) test
}

teardown() {
    sudo umount test
    cd /
    # remove temp directory
    temp_del "$WORKDIR"
}

# custom helper function
# create_file() {
#     local size="${1:-10M}"
#     local target_file="${2:-/dev/stdout}"
#     mkdir -p $(dirname "$target_file")
#     dd if=/dev/zero of="$target_file" bs="$size" count=1 conv=sparse status=none
# }

fill_to() {
    # creates a file such that the disk usage reaches the desired precentage
    local desired_percent="$(echo $1 | tr -d %)"
    local target_file="${2:-/dev/stdout}"

    mkdir -p $(dirname "$target_file")
    
    used_percent=$(df -P "$TESTDIR" | tail -1 | awk '{print $5}' | tr -d %)
    available_blocks=$(df -P "$TESTDIR" | tail -1 | awk '{print $4}')
    total_blocks=$(df -P "$TESTDIR" | tail -1 | awk '{print $2}')
    delta_percent=$((desired_percent - used_percent))

    if [[ -z $delta_percent ]] || [[ $delta_percent -le 0 ]]; then
        return
    fi
    
    # NOTE: on ext4 files seem to round up to nearest 4 blocks
    blocks_to_write=$((total_blocks * delta_percent / 100))
    # truncate any fractional value
    # https://unix.stackexchange.com/questions/89712/how-to-convert-floating-point-number-to-integer
    blocks_to_write=${blocks_to_write%.*}

    if [[ $blocks_to_write -gt $available_blocks ]]; then
        blocks_to_write=$available_blocks
    fi

    # NOTE: df doesn't count sparse files as used space
    # dd if=/dev/zero of="$target_file" bs=1024 count=$blocks_to_write  status=none
    # # overwrite the file with zeroes; faster way to de-sparsify the file
    # shred -n 0 -z "$target_file"

    # write in larger bs chunks to speed it up
    blocks_to_write=$((blocks_to_write / 4))
    blocks_to_write=${blocks_to_write%.*}

    dd if=/dev/zero of="$target_file" bs=4096 count=$blocks_to_write status=none

    # echo "Filling to $desired_percent%"
    # df -P test
}

# NOTE: disk usage percent is flaky and I can't seem to get a desired value

@test "already under threshold" {
    # disk is under the threshold and no files are deleted
    fill_to 10% test/2021-01-01/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 90

    assert_success
    assert_file_exist test/2021-01-01/conn.log.gz
}

@test "clean one day" {
    # delete one day to go under threshold
    fill_to 25% test/2021-01-01/conn.log.gz
    fill_to 50% test/2021-01-02/conn.log.gz
    fill_to 75% test/2021-01-03/conn.log.gz
    fill_to 95% test/2021-01-04/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 90

    assert_success
    assert_file_not_exist test/2021-01-01
    assert_file_exist test/2021-01-02/conn.log.gz
    assert_file_exist test/2021-01-03/conn.log.gz
    assert_file_exist test/2021-01-04/conn.log.gz
}

@test "clean multiple days" {
    # delete two days to go under threshold
    fill_to  5% test/2021-01-01/conn.log.gz
    fill_to 10% test/2021-01-02/conn.log.gz
    fill_to 50% test/2021-01-03/conn.log.gz
    fill_to 91% test/2021-01-04/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 90

    assert_success
    assert_file_not_exist test/2021-01-01
    assert_file_not_exist test/2021-01-02
    assert_file_exist test/2021-01-03/conn.log.gz
    assert_file_exist test/2021-01-04/conn.log.gz
}

@test "missing days" {
    # delete the oldest day regardless how old it is
    fill_to  5% test/2021-01-01/conn.log.gz
    fill_to 10% test/2021-02-02/conn.log.gz
    fill_to 50% test/2021-03-03/conn.log.gz
    fill_to 91% test/2021-12-31/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 90

    assert_success
    assert_file_not_exist test/2021-01-01
    assert_file_not_exist test/2021-02-02
    assert_file_exist test/2021-03-03/conn.log.gz
    assert_file_exist test/2021-12-31/conn.log.gz
}

@test "skip extra directories" {
    # do not delete anything outside of dated directories
    fill_to 91% test/do_not_delete/conn.log.gz
    fill_to 92% test/2021-01-01/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 90

    assert_failure
    assert_file_exist test/do_not_delete/conn.log.gz
    assert_file_not_exist test/2021-01-01
}

@test "skip today" {
    # do not delete today's logs even if they are the only logs
    local today=$(date -u "+%Y-%m-%d")
    fill_to 91% test/$today/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 90

    assert_failure
    assert_file_exist test/$today/conn.log.gz
}

@test "clean failure" {
    # exit with failure if cannot get disk below threshold
    fill_to 91% test/2021-01-01/conn.log.gz
    # make file immutable to prevent deletion
    sudo chattr +i test/2021-01-01/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 90

    assert_failure
    assert_file_exist test/2021-01-01/conn.log.gz
}

@test "multiple sensors" {
    # delete multiple directories with the same date
    fill_to 30% test/sensor1/2021-01-01/conn.log.gz
    fill_to 60% test/sensor2/2021-01-01/conn.log.gz
    fill_to 90% test/sensor3/2021-01-01/conn.log.gz
    fill_to 91% test/sensor4/2021-01-02/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 90

    assert_success
    assert_file_not_exist test/sensor1/2021-01-01
    assert_file_not_exist test/sensor2/2021-01-01
    assert_file_not_exist test/sensor3/2021-01-01
    assert_file_exist test/sensor4/2021-01-02
}

@test "different threshold" {
    # delete files checking a custom threshold
    fill_to 25% test/2021-01-01/conn.log.gz
    fill_to 51% test/2021-01-02/conn.log.gz

    run $BATS_TEST_DIRNAME/../zeek_log_clean.sh --dir "$TESTDIR" --threshold 50

    assert_success
    assert_file_not_exist test/2021-01-01
    assert_file_exist test/2021-01-02
}
