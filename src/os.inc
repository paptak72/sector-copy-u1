; Atari XL/XE OS and hardware symbols used by Sector Copy U1.

DOSVEC  = $000A
APPMHI  = $000E
RTCLOK  = $0012
LMARGN  = $0052
RMARGN  = $0053
ROWCRS  = $0054
COLCRS  = $0055
SAVMSC  = $0058
OLDROW  = $005A
OLDCOL  = $005B
OLDADR  = $005E
COLOR1  = $02C5
COLOR2  = $02C6
COLOR4  = $02C8
CRSINH  = $02F0
CHBAS   = $02F4
CH      = $02FC
MEMLO   = $02E7
MEMTOP  = $02E5
PDVMSK  = $0247
SHPDVS  = $0248
PDMSK   = $0249
CDTMV1  = $0218
CDTMV2  = $021A
CDTMV3  = $021C
CDTMV4  = $021E
CDTMV5  = $0220
VVBLKI  = $0222
VVBLKD  = $0224

DDEVIC  = $0300
DUNIT   = $0301
DCOMND  = $0302
DSTATS  = $0303
DBUFLO  = $0304
DBUFHI  = $0305
DTIMLO  = $0306
DUNUSE  = $0307
DBYTLO  = $0308
DBYTHI  = $0309
DAUX1   = $030A
DAUX2   = $030B

IOCB0   = $0340
ICCOM   = IOCB0 + 2
ICBAL   = IOCB0 + 4
ICBAH   = IOCB0 + 5
ICBLL   = IOCB0 + 8
ICBLH   = IOCB0 + 9
ICAX1   = IOCB0 + 10
ICAX2   = IOCB0 + 11

CIOV    = $E456
SIOV    = $E459
SYSVBV  = $E45F
XITVBV  = $E462
COLDSV  = $E477

PORTB   = $D301
; Rejestr klawiszy konsoli. Bity sa aktywne zerem: bit 0 START, bit 1 SELECT,
; bit 2 OPTION. Klawisze te nie trafiaja do handlera K:, dlatego potwierdzenia
; operacji destrukcyjnych musza czytac CONSOL bezposrednio.
CONSOL  = $D01F
V_SETME = $07F1
V_POPME = $07F4
JSECTOR_IO = $070C
MEMREIX = $0787

CIO_GETCHR = $07
CIO_PUTCHR = $0B
CIO_OPEN   = $03
CIO_CLOSE  = $0C

SIO_READ    = $40
SIO_WRITE   = $80
SIO_OK      = $01

CMD_HSI     = $3F
CMD_PERCOM  = $4E
CMD_SET_PERCOM = $4F
CMD_PUT     = $50
CMD_READ    = $52
CMD_STATUS  = $53
CMD_WRITE   = $57
CMD_FORMAT  = $21
CMD_FORMAT_ED = $22

ATASCII_CLEAR = $7D
ATASCII_EOL   = $9B
ATASCII_ESC   = $1B
; ---------------------------------------------------------------------------
; Wybrane adresy Atari XL/XE OS i rejestrow sprzetowych
; ---------------------------------------------------------------------------
; Nazwy sa celowo lokalne dla projektu: pozwala to analizowac zrodla bez
; koniecznosci posiadania dodatkowego pakietu include cc65. Adresy $02xx/$03xx
; sa zmiennymi i wektorami systemu, $D2xx to POKEY, $D3xx PIA/PORTB, a $E4xx
; wejscia ROM-u. Kierunki DSTATS sa wartosciami DCB przed operacja; po powrocie
; to samo pole zawiera status ($01 = sukces).
