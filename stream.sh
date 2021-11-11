#!/bin/bash

FFMPEGBIN="/usr/bin/ffmpeg"
V4LBIN="/usr/bin/v4l2-ctl"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -d|--device)
      V4LDEVICE="$2"
      shift
      shift
      ;;
    -f|--fps)
      FPS="$2"
      shift
      shift
      ;;
    -r|--resolution)
      RES="$2"
      shift
      shift
      ;;
   *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

PIXFMT="YUYV"

if [ "$RES" = "" ]; then
        RES="1920x1080";
fi
IFS="x" read RESX RESY <<< "$RES"
RESX=$(expr "$RESX" + 0)
RESY=$(expr "$RESY" + 0)

if [ "$FPS" = "" ]; then
        FPS="25";
fi
FPS=$(expr "$FPS" + 0)

if [ "$V4LDEVICE" = "" ]; then
        echo "Usage: $0 -d device"
        echo "Devices found :"
        for i in /sys/class/video4linux/*
        do
                p=$(readlink -f "$i")
                dev=$(basename $i)
                read manufacturer <$p/../../../manufacturer
                read product <$p/../../../product
                read name <$i/name
                read idev <$i/dev
                echo $dev $manufacturer $name dev $idev
                dev=""
        done
elif [ ! -c /dev/$V4LDEVICE ]; then
        echo "Device $V4LDEVICE not found";
        exit 1;
fi

## Try requested format
VALIDFMT=$( $V4LBIN -d /dev/$V4LDEVICE --list-frameintervals width=$RESX,height=
$RESY,pixelformat=$PIXFMT | grep "$FPS.000 fps" )

if [ "$VALIDFMT" = "" ]; then
        echo "Format [ width=$RESX height=$RESY pixelfmt=$PIXFMT fps=$FPS ] not
supported"
        echo "Supported formats :"
        $V4LBIN -d /dev/$V4LDEVICE --list-formats-ext

        exit 1
fi

echo "Setting capture format to [ width=$RESX,height=$RESY,pixelformat=$PIXFMT ]
"
$V4LBIN -d /dev/$V4LDEVICE --set-fmt-video width=$RESX,height=$RESY,pixelformat=
$PIXFMT
echo "Setting capture rate to $FPS FPS"
$V4LBIN -d /dev/$V4LDEVICE --set-parm $FPS

echo "Capture format as set"
$V4LBIN -d /dev/$V4LDEVICE --get-fmt-video --get-parm

# CPU encode
#       -c:v libx264 \
#       -crf 23 -maxrate 2M -bufsize 2M \
# GPU encode
#       -vf 'format=nv12,hwupload' -c:v h264_vaapi -qp 28 \

# Local target
#       -f flv rtmp://localhost:1935/live/live

"$FFMPEGBIN" \
        -vaapi_device /dev/dri/renderD128 \
        -hide_banner \
        -r "$FPS" \
        -f v4l2 \
        -i "/dev/$V4LDEVICE" \
        -f alsa -channels 2 -i hw:CARD=HDMI,DEV=0 \
        -vf 'format=nv12,hwupload' -c:v h264_vaapi -qp 28 \
        -c:a aac -b:a 128k \
        -f mpegts udp://192.168.254.129:5001

