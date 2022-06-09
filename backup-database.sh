#!/bin/sh

#------------------------------------------------------------------------------
#
#   システム名      :   医療情報システム
#
#   サブシステム名  :   バックアップ
#
#   プログラム名    :   backup-database
#
#   モジュール名    :   backup-database.sh
#
#   処理内容        :   データベースの圧縮バックアップ
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
MYSQLDUMP=/usr/bin/mysqldump
PG_DUMP=/usr/bin/pg_dump

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
    # データベース名
    local _dbname=""
    # DBユーザ
    local _dbuser=""
    # DBパスワード
    local _dbpass=""
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
    #   MySQL/MariaDB
    #---------------------------------------
    # 対象DB検索
    for idx1 in ${!MYSQL_DBNAME[@]};do
        # データベース名
        _dbname=${MYSQL_DBNAME[$idx1]}
        # DBユーザ
        _dbuser=${MYSQL_DBUSER[$idx1]}
        # DBパスワード
        _dbpass=${MYSQL_DBPASS[$idx1]}
        # ファイル履歴
        _bktype=${MYSQL_BKTYPE[$idx1]}

        # DBバックアップ
        mysql_dump ${_dbname} ${_dbuser} ${_dbpass} ${_bktype}
    done

    #---------------------------------------
    #   PostgreSQL
    #---------------------------------------
    # 対象DB検索
    for idx1 in ${!PGSQL_DBNAME[@]};do
        # データベース名
        _dbname=${PGSQL_DBNAME[$idx1]}
        # DBユーザ
        _dbuser=${PGSQL_DBUSER[$idx1]}
        # DBパスワード
        _dbpass=${PGSQL_DBPASS[$idx1]}
        # ファイル履歴
        _bktype=${PGSQL_BKTYPE[$idx1]}

        # DBバックアップ
        pgsql_dump ${_dbname} ${_dbuser} ${_dbpass} ${_bktype}
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
    find ${BACKUP} -maxdepth 1 -mtime +${PERIOD} -name '*.dump.gz' -exec rm -f {} \;

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
#    関数名 : mysql_dump
#
#    内  容 : MySQL/MariaDBの圧縮ダンプ
#
#    引  数 : 1) データベース名
#             2) DBユーザ
#             3) DBパスワード
#             4) ファイル履歴
#                ・week      : 週(デフォルト)
#                ・day       : 日
#                ・week/hour : 週-時
#                ・day/hour  : 日-時
#
#    戻り値 : なし
#
#------------------------------------------------------------------------------
function mysql_dump() {
    # データベース名
    local _dbname=$1
    # DBユーザ
    local _dbuser=$2
    # DBパスワード
    local _dbpass=$3
    # ファイル名
    local _bkfile=""

    # ファイル履歴の判定
    if [ "$4" == "day/hour" ];then
        # ファイル名の生成
        _bkfile=${_dbname}_${DAY}-${HOUR}.dump.gz
    elif [ "$4" == "week/hour" ];then
        # ファイル名の生成
        _bkfile=${_dbname}_${WEEK}-${HOUR}.dump.gz
    elif [ "$4" == "day" ];then
        # ファイル名の生成
        _bkfile=${_dbname}_${DAY}.dump.gz
    else
        # ファイル名の生成
        _bkfile=${_dbname}_${WEEK}.dump.gz
    fi

    # DUMP実行
    ${MYSQLDUMP} -u ${_dbuser} -p${_dbpass} --single-transaction --hex-blob ${_dbname} 2>/dev/null | gzip > ${BACKUP}${_bkfile}
    if [ $? -eq 0 ];then
        # バックアップ転送対象
        add_backup ${BACKUP}${_bkfile} ${_dbname}
    fi

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
#
#    関数名 : pgsql_dump
#
#    内  容 : PostgreSQLの圧縮ダンプ
#
#    引  数 : 1) データベース名
#             2) DBユーザ
#             3) DBパスワード
#             4) ファイル履歴
#                ・week      : 週(デフォルト)
#                ・day       : 日
#                ・week/hour : 週-時
#                ・day/hour  : 日-時
#
#    戻り値 : なし
#
#------------------------------------------------------------------------------
function pgsql_dump() {
    # データベース名
    local _dbname=$1
    # DBユーザ
    local _dbuser=$2
    # DBパスワード
    local _dbpass=$3
    # ファイル名
    local _bkfile=""

    # ファイル履歴の判定
    if [ "$4" == "day/hour" ];then
        # ファイル名の生成
        _bkfile=${_dbname}_${DAY}-${HOUR}.dump.gz
    elif [ "$4" == "week/hour" ];then
        # ファイル名の生成
        _bkfile=${_dbname}_${WEEK}-${HOUR}.dump.gz
    elif [ "$4" == "day" ];then
        # ファイル名の生成
        _bkfile=${_dbname}_${DAY}.dump.gz
    else
        # ファイル名の生成
        _bkfile=${_dbname}_${WEEK}.dump.gz
    fi

    # DUMP実行
    export PGPASSWORD=${_dbpass}
    ${PG_DUMP} -U ${_dbuser} -w ${_dbname} | gzip > ${BACKUP}${_bkfile}
    if [ $? -eq 0 ];then
        # バックアップ転送対象
        add_backup ${BACKUP}${_bkfile} ${_dbname}
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
