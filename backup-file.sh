#!/bin/sh

#------------------------------------------------------------------------------
#
#   システム名      :   医療情報システム
#
#   サブシステム名  :   バックアップ
#
#   プログラム名    :   backup-file
#
#   モジュール名    :   backup-file.sh
#
#   処理内容        :  ファイルの圧縮バックアップ
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
#   関数名  : main
#
#   内  容  : 主処理
#
#   引  数  : なし
#
#   戻り値  : なし
#
#------------------------------------------------------------------------------
function main() {
    # tarファイル名
    local _tar=""
    # ファイル名
    local _bkfile=""
    # バックアップ名
    local _name=""
    # 除外ファイル名
    local _exclude=""

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
    #   crontab
    #---------------------------------------
    # 対象ユーザ検索
    for cron_userid in ${CRON_USERID[@]};do
        # crontab
        crontab -u ${cron_userid} -l > ${BACKUP}${cron_userid}_${WEEK}.crontab 2>/dev/null
        # ファイルパスの格納
        BK_PATH+=(${BACKUP}${cron_userid}_${WEEK}.crontab)
        # フォルダ名の格納
        BK_NAME+=("cron")
    done

    #---------------------------------------
    #   ディレクトリ/ファイル
    #---------------------------------------
    # 対象検索
    for idx1 in ${!FILE_NAME[@]};do
        # 初期化
        _name=""
        _exclude=""
        # tarファイルの指定
        _tar=${BACKUP}${FILE_NAME[$idx1]}.tar

        # ファイル履歴の判定
        if [ "${FILE_BKTYPE[$idx1]}" == "day/hour" ];then
            # ファイル名の生成
            _bkfile=${BACKUP}${FILE_NAME[$idx1]}_${DAY}-${HOUR}.tar.gz
        elif [ "${FILE_BKTYPE[$idx1]}" == "week/hour" ];then
            # ファイル名の生成
            _bkfile=${BACKUP}${FILE_NAME[$idx1]}_${WEEK}-${HOUR}.tar.gz
        elif [ "${FILE_BKTYPE[$idx1]}" == "day" ];then
            # ファイル名の生成
            _bkfile=${BACKUP}${FILE_NAME[$idx1]}_${DAY}.tar.gz
        else
            # ファイル名の生成
            _bkfile=${BACKUP}${FILE_NAME[$idx1]}_${WEEK}.tar.gz
        fi
        # 除外ファイル検索
        for fileexfile in ${FILE_EXFILE[$idx1]};do
            # 初回判定
            if [ "${_exclude}" == "" ];then
                # 除外ファイルの作成
                _exclude="--exclude ${fileexfile}"
            else
                # 除外ファイルの作成
                _exclude=${_exclude}" --exclude ${fileexfile}"
            fi
        done
        # 対象ファイル検索
        for filepath in ${FILE_PATH[$idx1]};do
            # 初回判定
            if [ "${_name}" == "" ];then
                # tarファイルの作成
                tar -cvf ${_tar} ${_exclude} ${filepath} >/dev/null 2>&1
            else
                # tarファイルの追加
                tar -rvf ${_tar} ${_exclude} ${filepath} >/dev/null 2>&1
            fi
            # バックアップ名
            _name=${FILE_NAME[$idx1]}
        done
        # tar.gzファイルの作成
        tar -zcvf ${_bkfile} ${_tar} >/dev/null 2>&1
        # 結果判定
        if [ $? -eq 0 ];then
            # tarファイルの削除
            rm -f ${_tar}
            # ファイルパスの格納
            BK_PATH+=(${_bkfile})
            # フォルダ名の格納
            BK_NAME+=(${_name})
        fi
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
    find ${BACKUP} -maxdepth 1 -mtime +${PERIOD} -name '*.crontab' -exec rm -f {} \;
    find ${BACKUP} -maxdepth 1 -mtime +${PERIOD} -name '*.tar' -exec rm -f {} \;
    find ${BACKUP} -maxdepth 1 -mtime +${PERIOD} -name '*.tar.gz' -exec rm -f {} \;

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
