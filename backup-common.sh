#------------------------------------------------------------------------------
#
#   システム名      :   医療情報システム
#
#   サブシステム名  :   バックアップ
#
#   プログラム名    :   backup-common
#
#   モジュール名    :   backup-common.sh
#
#   処理内容        :   共通関数
#
#   注意事項        :
#
#   作成日(担当者)  :   2018/04/18(山脇)
#   修正日(担当者)  :
#
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
#   初期設定
#------------------------------------------------------------------------------
#---------------------------------------
#   変数定義
#---------------------------------------
# バックアップ配列
BK_PATH=()
BK_NAME=()

#------------------------------------------------------------------------------
#
#   関数名  : smb_put
#
#   内  容  : Sambaサーバへのファイルコピー
#
#   引  数  : 1) サーバ名/共有名
#                例)192.168.0.1/share
#             2) SMBユーザ
#                例)guest
#             3) SMBパスワード
#                例)guest
#             4) コピー元(ファイル名)
#                例)/backup/database.dump.gz
#             5) コピー先(フォルダ名)
#                例)/backup
#
#   戻り値 : なし
#
#------------------------------------------------------------------------------
function smb_put() {
    # サーバ名
    local _server=$1
    # ユーザ
    local _smbuser=$2
    # パスワード
    local _smbpass=$3

    # ファイル名
    local _filename=`/usr/bin/basename $4`

    # コマンド
    local _mkdir="mkdir $5"
    local _copy="put $4 $5/${_filename}"

    #---------------------------------------
    #   コマンド実行
    #---------------------------------------
    # ディレクトリ作成
    /usr/bin/smbclient "//${_server}" -U ${_smbuser}%${_smbpass} -c "${_mkdir}" >/dev/null 2>&1
    # ファイル転送
    /usr/bin/smbclient "//${_server}" -U ${_smbuser}%${_smbpass} -c "${_copy}" >/dev/null 2>&1

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
#
#   関数名  : ftp_put
#
#   内  容  : FTPサーバへのファイル転送
#
#   引  数  : 1) サーバ名
#                例)192.168.0.1
#             2) FTPユーザ
#                例)guest
#             3) FTPパスワード
#                例)guest
#             4) コピー元(ファイル名)
#                例)/backup/database.dump.gz
#             5) コピー先(フォルダ名)
#                例)/mnt/array1/share/backup
#
#   戻り値  : なし
#
#------------------------------------------------------------------------------
function ftp_put() {
    # サーバ名
    local _server=$1
    # ユーザ
    local _ftpuser=$2
    # パスワード
    local _ftppass=$3
    # コピー先
    local _copyto=$5

    # ディレクトリ名
    local _dirname=`/usr/bin/dirname $4`
    # ファイル名
    local _filename=`/usr/bin/basename $4`

    # 現在パスの退避
    local _pwd=$("pwd")
    # ディレクトリ移動
    cd ${_dirname}

# ftpコマンド実行(ヒアドキュメント)
/usr/bin/ftp -n <<END
open ${_server}
user ${_ftpuser} ${_ftppass}
binary
mkdir -p ${_copyto}
cd ${_copyto}
put ${_filename}
bye
END

    # パスの復元
    cd ${_pwd}

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
#
#   関数名  : sftp_put
#
#   内  容  : SSHサーバへのファイル転送
#
#   引  数  : 1) サーバ名
#                例)192.168.0.1
#             2) SSHユーザ
#                例)guest
#             3) SSHパスワード
#                例)guest
#             4) コピー元(ファイル名)
#                例)/backup/database.dump.gz
#             5) コピー先(フォルダ名)
#                例)/mnt/array1/share/backup
#
#   戻り値  : なし
#
#------------------------------------------------------------------------------
function sftp_put() {
    # サーバ名
    local _server=$1
    # ユーザ
    local _sshuser=$2
    # パスワード
    local _sshpass=$3
    # コピー元
    local _copyfrom=$4
    # コピー先
    local _copyto=$5

# sftpコマンド実行(ヒアドキュメント)
/usr/bin/sshpass -p ${_sshpass} /usr/bin/sftp ${_sshuser}@${_server} <<END
mkdir ${_copyto}
cd ${_copyto}
put ${_copyfrom}
END

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
#
#   関数名  : add_backup
#
#   内  容  : バックアップ転送対象への追加
#
#   引  数  : 1) 転送元ファイルパス
#                例)/backup/kanjadb.dump.gz
#                   /backup/home.tar.gz
#             2) 転送先サブフォルダ
#                例)kanjadb
#                   home
#
#   戻り値  : なし
#
#------------------------------------------------------------------------------
function add_backup() {
    # ファイルパス
    local _bkpath=$1
    # バックアップ名
    local _bkname=$2

    # ファイルパスの格納
    BK_PATH+=(${_bkpath})
    # バックアップ名の格納
    BK_NAME+=(${_bkname})

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
#
#   関数名  : send_backup
#
#   内  容  : バックアップファイルの転送
#
#   引  数  : なし
#
#   戻り値  : なし
#
#------------------------------------------------------------------------------
function send_backup() {
    # ファイルパス
    local _bkpath=""

    #---------------------------------------
    #   ファイル転送
    #---------------------------------------
    # バックアップファイルの転送
    for idx1 in ${!BK_PATH[@]};do
        # 転送形式の判定
        if [ "${SMB_SERVER}" != "" ];then
            # バックアップパスの生成
            if [ "${BK_NAME[$idx1]+_}" == "_" ];then
                _bkpath=${SMB_BACKUP}/${BK_NAME[$idx1]}
            else
                _bkpath=${SMB_BACKUP}
            fi
            # sambaクライアント
            smb_put ${SMB_SERVER} ${SMB_USERID} ${SMB_PASSWD} ${BK_PATH[$idx1]} ${_bkpath}
        elif [ "${FTP_SERVER}" != "" ];then
            # バックアップパスの生成
            if [ "${BK_NAME[$idx1]+_}" == "_" ];then
                _bkpath=${FTP_BACKUP}/${BK_NAME[$idx1]}
            else
                _bkpath=${FTP_BACKUP}
            fi
            # ftpクライアント
            ftp_put ${FTP_SERVER} ${FTP_USERID} ${FTP_PASSWD} ${BK_PATH[$idx1]} ${_bkpath}
        elif [ "${SSH_SERVER}" != "" ];then
            # バックアップパスの生成
            if [ "${BK_NAME[$idx1]+_}" == "_" ];then
                _bkpath=${SSH_BACKUP}/${BK_NAME[$idx1]}
            else
                _bkpath=${SSH_BACKUP}
            fi
            # sftpクライアント
            sftp_put ${SSH_SERVER} ${SSH_USERID} ${SSH_PASSWD} ${BK_PATH[$idx1]} ${_bkpath}
        fi
    done

    # 正常終了
    return 0
}

#------------------------------------------------------------------------------
