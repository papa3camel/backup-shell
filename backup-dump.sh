#!/bin/sh

#------------------------------------------------------------------------------
#
#   システム名      :   医療情報システム
#
#   サブシステム名  :   バックアップ
#
#   プログラム名    :   backup-dump
#
#   モジュール名    :   backup-dump.sh
#
#   処理内容        :   ファイルシステムのバックアップ
#
#   注意事項        :
#
#   作成日(担当者)  :   2018/04/18(山脇)
#   修正日(担当者)  :
#
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
#   関数宣言
#------------------------------------------------------------------------------
FUNC=/usr/local/bin/functions.sh
if [ -f ${FUNC} ];then
    . ${FUNC}
fi
COMN=/usr/local/bin/backup-common.sh
if [ -f ${COMN} ];then
    . ${COMN}
fi

#------------------------------------------------------------------------------
#   初期設定
#------------------------------------------------------------------------------
#---------------------------------------
#   定数定義
#---------------------------------------
# コマンドパス
if [ -f /sbin/sfdisk ];then
    SFDISK=/sbin/sfdisk
    BLKID=/sbin/blkid
    IP=/sbin/ip
    VGCFGBACKUP=/sbin/vgcfgbackup
else
    SFDISK=/usr/sbin/sfdisk
    BLKID=/usr/sbin/blkid
    IP=/usr/sbin/ip
    VGCFGBACKUP=/usr/sbin/vgcfgbackup
fi
if [ -f /sbin/dump ];then
    XFSDUMP=/sbin/xfsdump
    DUMP=/sbin/dump
    LVCREATE=/sbin/lvcreate
    LVCHANGE=/sbin/lvchange
    LVREMOVE=/sbin/lvremove
else
    XFSDUMP=/usr/sbin/xfsdump
    DUMP=/usr/sbin/dump
    LVCREATE=/usr/sbin/lvcreate
    LVCHANGE=/usr/sbin/lvchange
    LVREMOVE=/usr/sbin/lvremove
fi

# バックアップパス
BACKUP=/backup/
# PIDファイルパス
PID_PATH=/var/tmp/

# 日
DAY=$(date '+%d')
# 週
WEEK=$(date '+%w')
# 時
HOUR=$(date '+%H')

#------------------------------------------------------------------------------
#   設定ファイル
#------------------------------------------------------------------------------
CONF=/etc/backup.d/$(basename ${0%.*}).conf
if [ -f ${CONF} ];then
    . ${CONF}
fi


#------------------------------------------------------------------------------
#
#    関数名 : main
#
#    内  容 : 主処理
#
#    引  数 : なし
#
#    戻り値 : なし
#
#------------------------------------------------------------------------------
function main() {
    # ファイル名
    local _bkfile=""
    # デバイス名
    local _device=""
    # ボリュームグループ
    local _vgname=""
    # 論理ボリューム
    local _lvname=""
    # ファイルシステム
    local _fstype=""
    # スナップショット名
    local _snapnm=""
    # スナップショットサイズ
    local _snapsz=""
    # ファイル履歴
    local _bktype=""

    #---------------------------------------
    #   バックアップ保存日数
    #---------------------------------------
    # バックアップ保存日数
    if [ "${PERIOD}" == "" ];then
        # デフォルト値
        PERIOD=2
    else
        if [ ${PERIOD} -lt 1 ];then
            # デフォルト値
            PERIOD=2
        else
            # 日数 - 1
            PERIOD=`expr ${PERIOD} - 1`;
        fi
    fi

    #---------------------------------------
    #   バックアップ格納先
    #---------------------------------------
    # バックアップパスの判定
    if [ "${BACKUP}" == "" ];then
        # 異常終了
        return 1
    fi

    #---------------------------------------
    #   リモートマウント判定
    #---------------------------------------
    if [ "${MNT_FSTYPE}" != "" -a "${MNT_SERVER}" != "" -a "${MNT_MPOINT}" != "" ];then
        # アンマウント(念の為)
        umount ${MNT_MPOINT} >/dev/null 2>&1
        # オプション判定
        if [ "${MNT_OPTION}" == "" ];then
            # リモートマウント
            mount -t ${MNT_FSTYPE} ${MNT_SERVER} ${MNT_MPOINT}
        else
            # リモートマウント
            mount -t ${MNT_FSTYPE} -o ${MNT_OPTION} ${MNT_SERVER} ${MNT_MPOINT}
        fi
        if [ $? -ne 0 ];then
            # 異常終了
            return 1
        fi
    fi

    #---------------------------------------
    #   ログ削除
    #---------------------------------------
    # バックアップログ削除
    rm -f ${BACKUP}backup.log >/dev/null 2>&1
    # バックアップ転送対象
    add_backup ${BACKUP}backup.log ${WEEK}

    #---------------------------------------
    #   sfdiskの保存
    #---------------------------------------
    # デバイス検索
    for idx1 in ${!DEV_DEVICE[@]};do
        # デバイス名
        _device=${DEV_DEVICE[$idx1]}
        # ファイル名の生成
        _bkfile=sfdisk-${_device}_${WEEK}.txt
        # バックアップ
        ${SFDISK} -d /dev/${_device} > ${BACKUP}${_bkfile}
        if [ $? -eq 0 ];then
            # バックアップ転送対象
            add_backup ${BACKUP}${_bkfile} ${WEEK}
        fi
    done

    #---------------------------------------
    #   UUIDの保存
    #---------------------------------------
    # ファイル名の生成
    _bkfile=blkid_${WEEK}.txt
    # バックアップ
    ${BLKID} > ${BACKUP}${_bkfile}
    if [ $? -eq 0 ];then
        # バックアップ転送対象
        add_backup ${BACKUP}${_bkfile} ${WEEK}
    fi

    #---------------------------------------
    #   fstabの保存
    #---------------------------------------
    # ファイル名の生成
    _bkfile=fstab_${WEEK}.txt
    # バックアップ
    cat /etc/fstab > ${BACKUP}${_bkfile}
    if [ $? -eq 0 ];then
        # バックアップ転送対象
        add_backup ${BACKUP}${_bkfile} ${WEEK}
    fi

    #---------------------------------------
    #   ip addrの保存
    #---------------------------------------
    # ファイル名の生成
    _bkfile=ip-addr_${WEEK}.txt
    # バックアップ
    ${IP} addr > ${BACKUP}${_bkfile}
    if [ $? -eq 0 ];then
        # バックアップ転送対象
        add_backup ${BACKUP}${_bkfile} ${WEEK}
    fi

    #---------------------------------------
    #   /dev/sda1
    #---------------------------------------
    # ファイルシステム検索
    for idx1 in ${!DSK_DEVICE[@]};do
        # デバイス名
        _device=${DSK_DEVICE[$idx1]}
        # ファイルシステム
        _fstype=${DSK_FSTYPE[$idx1]}
        # ファイル履歴
        _bktype=${DSK_BKTYPE[$idx1]}

        # バックアップ
        disk_dump ${_device} ${_fstype} ${_bktype}
    done

    #---------------------------------------
    #   /dev/mapper
    #---------------------------------------
    # LVMファイルシステム検索
    for idx1 in ${!LVM_VGNAME[@]};do
        #---------------------------------------
        #   LVM定義のエクスポート
        #---------------------------------------
        if [ "${_vgname}" != "${LVM_VGNAME[$idx1]}" ];then
            # ファイル名の生成
            _bkfile=vgcfg-${LVM_VGNAME[$idx1]}_${WEEK}.dump
            # バックアップ
            ${VGCFGBACKUP} ${LVM_VGNAME[$idx1]} -f ${BACKUP}${_bkfile} >/dev/null 2>&1
            if [ $? -eq 0 ];then
                # バックアップ転送対象
                add_backup ${BACKUP}${_bkfile} ${WEEK}
            fi
        fi
        # ボリュームグループ
        _vgname=${LVM_VGNAME[$idx1]}
        # 論理ボリューム
        _lvname=${LVM_LVNAME[$idx1]}
        # ファイルシステム
        _fstype=${LVM_FSTYPE[$idx1]}
        # スナップショット名
        _snapnm=${LVM_SNAPNM[$idx1]}
        if [ "${_snapnm}" == "" ];then
            # スナップショットなし
            _snapnm="none"
        fi
        # スナップショットサイズ
        _snapsz=${LVM_SNAPSZ[$idx1]}
        if [ "${_snapsz}" == "" ];then
            # スナップショットの作成判定
            if [ "${_snapnm}" == "none" ];then
                # スナップショットなし
                _snapsz="none"
            else
                # スナップショットあり
                _snapsz="100%"
            fi
        fi
        # ファイル履歴
        _bktype=${LVM_BKTYPE[$idx1]}

        # バックアップ
        lvm_dump ${_vgname} ${_lvname} ${_fstype} ${_snapnm} ${_snapsz} ${_bktype}
    done

    #---------------------------------------
    #   ファイル転送
    #---------------------------------------
    # バックアップファイルの転送
    send_backup

    #---------------------------------------
    #   保存日前のファイルを削除
    #---------------------------------------
    # ファイル検索と削除
    find ${BACKUP} -maxdepth 1 -mtime +${PERIOD} -name '*.txt' -exec rm -f {} \;
    find ${BACKUP} -maxdepth 1 -mtime +${PERIOD} -name '*.dump' -exec rm -f {} \;

    #---------------------------------------
    #   リモートマウント判定
    #---------------------------------------
    if [ "${MNT_FSTYPE}" != "" -a "${MNT_SERVER}" != "" -a "${MNT_MPOINT}" != "" ];then
        # アンマウント
        umount ${MNT_MPOINT} >/dev/null 2>&1
    fi

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
#
#    関数名 : disk_dump
#
#    内  容 : ファイルシステムのダンプ
#
#    引  数 : 1) デバイス名
#             2) ファイルシステム
#                ・xfs      : xfs
#                ・ext      : ext3 or ext4
#             3) ファイル履歴
#                ・week      : 週(デフォルト)
#                ・day       : 日
#                ・week/hour : 週-時
#                ・day/hour  : 日-時
#
#    戻り値 : なし
#
#------------------------------------------------------------------------------
function disk_dump() {
    # デバイス名
    local _device=$1
    # ファイルシステム
    local _fstype=$2
    # ファイル名
    local _bkfile=""

    # ファイル履歴の判定
    if [ "$3" == "day/hour" ];then
        # ファイル名の生成
        _bkfile=${_device}_${DAY}-${HOUR}.dump
    elif [ "$3" == "week/hour" ];then
        # ファイル名の生成
        _bkfile=${_device}_${WEEK}-${HOUR}.dump
    elif [ "$3" == "day" ];then
        # ファイル名の生成
        _bkfile=${_device}_${DAY}.dump
    else
        # ファイル名の生成
        _bkfile=${_device}_${WEEK}.dump
    fi

    # ファイルシステムの判定
    if [ "${_fstype}" == "xfs" ];then
        # ダンプファイルの取得
        ${XFSDUMP} -l0 - /dev/${_device} 2>> ${BACKUP}backup.log > ${BACKUP}${_bkfile}
    else
        # ダンプファイルの取得
        ${DUMP} -0f - /dev/${_device} 2>> ${BACKUP}backup.log > ${BACKUP}${_bkfile}
    fi
    if [ $? -eq 0 ];then
        # バックアップ転送対象
        add_backup ${BACKUP}${_bkfile} ${WEEK}
    fi

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
#
#    関数名 : lvm_dump
#
#    内  容 : ファイルシステムのダンプ
#
#    引  数 : 1) ボリュームグループ
#             2) 論理ボリューム
#             3) ファイルシステム
#                ・xfs      : xfs
#                ・ext      : ext3 or ext4
#             4) スナップショット名
#                ・none     : スナップショットを作成しない
#                ・上記以外 : スナップショットを作成する
#             5) スナップショットサイズ
#                ・none     : スナップショットを作成しない
#                ・100%     : 空き領域全てを使用
#                ・ZZ9G     : ギガバイト指定
#                             例) 10G ･･･ 10ギガバイト
#             6) ファイル履歴
#                ・week      : 週(デフォルト)
#                ・day       : 日
#                ・week/hour : 週-時
#                ・day/hour  : 日-時
#
#    戻り値 : なし
#
#------------------------------------------------------------------------------
function lvm_dump() {
    # ボリュームグループ
    local _vgname=$1
    # 論理ボリューム
    local _lvname=$2
    # ファイルシステム
    local _fstype=$3
    # スナップショット名
    local _snapnm=$4
    # スナップショットサイズ
    local _snapsz=$5
    # ファイル名
    local _bkfile=""
    # ステータス
    local _status=0

    # マウントポイントの判定
    if [ "${SNAP}" == "" ];then
        # マウントポイントの指定
        SNAP=/mnt/snap
    fi

    # ファイル履歴の判定
    if [ "$6" == "day/hour" ];then
        # ファイル名の生成
        _bkfile=${_vgname}-${_lvname}_${DAY}-${HOUR}.dump
    elif [ "$6" == "week/hour" ];then
        # ファイル名の生成
        _bkfile=${_vgname}-${_lvname}_${WEEK}-${HOUR}.dump
    elif [ "$6" == "day" ];then
        # ファイル名の生成
        _bkfile=${_vgname}-${_lvname}_${DAY}.dump
    else
        # ファイル名の生成
        _bkfile=${_vgname}-${_lvname}_${WEEK}.dump
    fi

    # スナップショットの作成判定
    if [ "${_snapnm}" != "none" -a "${_snapsz}" != "none" ];then
        # マウントポイントの判定
        if [ -d ${SNAP} ];then
            # スナップショットのアンマウント(念の為)
            umount ${SNAP} >/dev/null 2>&1
        else
            # マウントポイントの作成
            mkdir -p ${SNAP} >/dev/null 2>&1
        fi
        # スナップショットの削除(念の為)
        ${LVREMOVE} -f /dev/${_vgname}/${_snapnm} >/dev/null 2>&1
        # スナップショットサイズの判定
        if [ "${_snapsz}" != "100%" ];then
            # スナップショットの作成
            ${LVCREATE} -s -L ${_snapsz} -n ${_snapnm} /dev/${_vgname}/${_lvname} >/dev/null 2>&1
        else
            # スナップショットの作成
            ${LVCREATE} -s -l 100%FREE -n ${_snapnm} /dev/${_vgname}/${_lvname} >/dev/null 2>&1
        fi
        if [ $? -eq 0 ];then
            # スナップショットのマウント
            mount -o ro /dev/${_vgname}/${_snapnm} ${SNAP} >/dev/null 2>&1
            if [ $? -ne 0 ];then
                # スナップショットのマウント(uuid未使用)
                mount -o nouuid -o ro /dev/${_vgname}/${_snapnm} ${SNAP}
            fi
            if [ $? -eq 0 ];then
                # ファイルシステムの判定
                if [ "${_fstype}" == "xfs" ];then
                    # ダンプファイルの取得
                    ${XFSDUMP} -l0 - /dev/${_vgname}/${_snapnm} 2>> ${BACKUP}backup.log > ${BACKUP}${_bkfile}
                else
                    # ダンプファイルの取得
                    ${DUMP} -0f - /dev/${_vgname}/${_snapnm} 2>> ${BACKUP}backup.log > ${BACKUP}${_bkfile}
                fi
                if [ $? -eq 0 ];then
                    # バックアップ転送対象
                    add_backup ${BACKUP}${_bkfile} ${WEEK}

                    # バックアップ済
                    _status=1
                fi
                # スナップショットのアンマウント
                umount ${SNAP}
            fi
        fi
        # スナップショットの削除
        ${LVREMOVE} -f /dev/${_vgname}/snap >/dev/null 2>&1
    fi

    # バックアップ判定
    if [ ${_status} -eq 0 ];then
        # ファイルシステムの判定
        if [ "${_fstype}" == "xfs" ];then
            # ダンプファイルの取得
            ${XFSDUMP} -l0 - /dev/${_vgname}/${_lvname} 2>> ${BACKUP}backup.log > ${BACKUP}${_bkfile}
        else
            # ダンプファイルの取得
            ${DUMP} -0f - /dev/${_vgname}/${_lvname} 2>> ${BACKUP}backup.log > ${BACKUP}${_bkfile}
        fi
        if [ $? -eq 0 ];then
            # バックアップ転送対象
            add_backup ${BACKUP}${_bkfile} ${WEEK}
        fi
    fi

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
#   プログラム実行
#------------------------------------------------------------------------------
# PIDファイル
PIDFILE=${PID_PATH}$(basename ${0%.*}).pid

# プロセス実行中の判定
check_pid ${PIDFILE}
if [ $? -eq 0 ];then
    # PIDファイルの作成
    echo $$ > ${PIDFILE}

    # 主処理
    main

    # PIDファイルの削除
    rm -f ${PIDFILE}
fi

# 正常終了
exit 0

#------------------------------------------------------------------------------
