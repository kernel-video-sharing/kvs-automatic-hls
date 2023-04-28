#!/usr/bin/env bash
#
# Description: Scripts Convert MP4 to HLS
# Version: 1.0.0 RC
# Author: PoSir
# Created: 2023-05-01
# Modified: 2023-05-05
# Usage: ./_convert.sh [options] [arguments]
# About custom more rclone flag check Doc, https://rclone.org/flags/
#

### CUSTOM BEGIN ###
ROOT_DIR=$(pwd);               # Project ROOT Dir
HLS_TIME=10;                   # HLS Duration Setting, Default:10
SYNC_ENABLE=1;                 # IF NEED SYNC change to 1, Default:0;
SYNC_DELETE=0;                 # IF Want Delete after generating HLS and Sync to Remote change to 1, Default:0;
SYNC_REMOTE="S3:cluster";         # sync to aws s3, example:  HOST:bucket
SYNC_CMD="rclone -v copy --fast-list --size-only --max-backlog 999999 --ignore-existing %s ${SYNC_REMOTE}%s --exclude=*.mp4";    # to saving cost, default: Do not Sync MP4 Files --config ${ROOT_DIR}/rclone.conf
FFMPEG_CMD="ffmpeg -hide_banner -loglevel error -i %s -codec: copy -f hls -start_number 0 -hls_time ${HLS_TIME} -hls_list_size 0 -hls_segment_filename %s -hls_playlist_type vod -hls_base_url %s %s";
### CUSTOM END   ###


### ================================###
### Do not modify the line below    ###
### if you don't know what it does  ###
### ================================###
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help  Display this help message";
    echo "  -f, --file  Specify a file to process";
    echo "  -d, --directory Specify a directory to process";
    echo "  -m, --monitor Monitoring of file changes, real-time transcoding HLS, Must include --directory value";
}

process_hls() {
  declare -g SYNC_AWS;
  declare -g SYNC_ENABLE;
  declare -g SYNC_DELETE;

  local SOURCE_FILE=$1
  if [ -z "${SOURCE_FILE}" ] || [ ! -f "${SOURCE_FILE}" ]; then
    echo "Error: file not provided or the file does not exist";
    exit 1
  fi

  local SOURCE_PATH=$(dirname "$SOURCE_FILE");
  local SOURCE_SYNC="${SOURCE_PATH//\/www\/wwwroot\/yunclip.com/}";
  local ORIGIN_NAME=$(basename "$SOURCE_FILE");
  local ORIGIN_NOEXT="${ORIGIN_NAME%.*}";

  echo -e "Work Directory: ${SOURCE_PATH}";
  echo -e "Full FileName: ${ORIGIN_NAME} , Without Extension: ${ORIGIN_NOEXT}";
  cd "${SOURCE_PATH}" || exit 1;

  # Custom HLS Transcoding
  local HLS_DEST="${ORIGIN_NOEXT}";
  [[ ! -d "${HLS_DEST}" ]] && mkdir "${HLS_DEST}"
  echo -e "HLS Dest Directory: ${HLS_DEST}";
  if [[ -f "${ORIGIN_NOEXT}.m3u8" ]]; then
    echo -e " HLS File Exists,Skip Process...";
  else
    echo -e " Generate the HLS......";
  ffmpeg_command=$(printf "${FFMPEG_CMD}" "${SOURCE_FILE}" "${HLS_DEST}/%03d.ts" "${HLS_DEST}/" "${ORIGIN_NOEXT}.m3u8")
  ${ffmpeg_command};
  echo -e " Generate Done!";
fi
  unset "${SOURCE_FILE}";

  # Custom Sync use RClone
  echo -e "SYNC Object Target: ${SOURCE_SYNC}";
  command_sync=$(printf "${SYNC_CMD}" "${SOURCE_PATH}" "${SOURCE_SYNC}")
  echo -e "${command_sync}";
  if [ "${SYNC_ENABLE}" -eq 1 ] ; then
    echo -e "   Sync Begin ....";
    ${command_sync};
    echo -e "   Sync End,Done......";
  else
    echo -e "   Sync Not Enable,Skip......";
  fi
  ## Clear, if Storage Servers is Full,Enable it, workflow : local generate m3u8,ts => upload m3u8,ts to remote => delete local m3u8,ts;
  if [ "${SYNC_DELETE}" -eq 1 ]; then
    echo -e "   Delete Local HLS Resource!";
    [[ -f "${ORIGIN_NOEXT}.m3u8" ]] && rm -rf "${ORIGIN_NOEXT}.m3u8";
    [[ -d "${HLS_DEST}" ]] && rm -rf "${HLS_DEST}";
  fi
}

file="";
directory="";
monitor=0;
dry_run=0;

while getopts ":hf:d:m:" opt; do
  case ${opt} in
    h | help )
      show_help
      exit 0
      ;;
    f | file )
      dry_run=1;
      file=$OPTARG
      ;;
    d | directory )
      directory=$OPTARG
      ;;
    m | monitor )
      monitor=1;
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." 1>&2
      exit 1
      ;;
  esac
done

# Single Files Test
if [ "${dry_run}" -eq 1 ]; then
  process_hls "${file}";
  exit 1;
fi

# Monitor Directory
if [ "${monitor}" -eq 1 ]; then
  # Detect Directory Exist
  if [[ ! -d "${directory}" ]] || [[ -z "${directory}" ]]; then
    echo -e "The Directory does not exist";
    exit 1;
  fi
  # Detect inotify-tools
  INOTIFYWAIT_BIN=$(which inotifywait);
  if [[ ! -z "${INOTIFYWAIT_BIN}" ]]; then
    echo -e "inotifywait is not installed,please install first";
    exit 1;
  fi
  # Loop Monitor File Change
  while read -r fullpath; do
      SOURCE_FILE=$fullpath
      SOURCE_PATH=$(dirname "$SOURCE_FILE");
      ORIGIN_NAME=$(basename "$SOURCE_FILE");
      ORIGIN_NOEXT="${ORIGIN_NAME%.*}";
      [[ "${SOURCE_FILE}" != *"preview"* ]] || continue
      process_hls "${fullpath}";
  done < <(inotifywait -m -r --format '%w%f' --include "\.mp4" -e attrib "${directory}")
  unset $fullpath;
  exit 1;
fi

# Process Exist File
if [[ ! -d "${directory}" ]] || [[ -z "${directory}" ]]; then
  echo -e "The Directory does not exist, please ./$0 -h see help";
  exit 1;
fi
while read -r fullpath; do
    echo -e "[Info] Processing: ${fullpath}";
    SOURCE_FILE=$fullpath
    SOURCE_PATH=$(dirname "$SOURCE_FILE");
    ORIGIN_NAME=$(basename "$SOURCE_FILE");
    ORIGIN_NOEXT="${ORIGIN_NAME%.*}";
    [[ "${SOURCE_FILE}" != *"preview"* ]] || continue
    process_hls "${fullpath}";
done < <(find "${directory}" -type f -name "*.mp4")

