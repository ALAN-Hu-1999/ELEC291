; Following code is done for using the math32.inc
$NOLIST
$MODLP51
$LIST

org 0000H
   ljmp MyProgram

DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5

BSEG
mf: dbit 1

$NOLIST
$include(math32.inc)
$LIST

; These 'equ' must match the hardware wiring
; They are used by 'LCD_4bit.inc'
LCD_RS equ P1.1
LCD_RW equ P1.2
LCD_E  equ P1.3
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
$NOLIST
$include(LCD_4bit.inc)
$LIST

CSEG

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))

InitSerialPort: 
; Debouncethe reset button! 
	mov R1,#222 
	mov R0,#166 
	djnz R0,$	; 3 cycles=22.51us 
	djnz R1,$-4	; 22.51us*222=4.998ms
; Configure serial port and baud rate 
	orl PCON,#0x80 
	mov SCON,#0x52 
	mov BDRCON,#0x00 
	mov BRL,#BRG_VAL 
	mov BDRCON,#0x1E; BRR|TBCK|RBCK|SPD 
	ret


CSEG


; seems to be a better version of setting up SPI
CE_ADC    EQU  P2.0 
MY_MOSI   EQU  P2.1 
MY_MISO   EQU  P2.2 
MY_SCLK   EQU  P2.3 


INI_SPI: 
    setb MY_MISO          ; Make MISO an input pin 
    clr MY_SCLK           ; Mode 0,0 default 
    ret
DO_SPI_G: 
    mov R1, #0            ; Received byte stored in R1 
    mov R2, #8            ; Loop counter (8-bits) 
DO_SPI_G_LOOP: 
    mov a, R0             ; Byte to write is in R0 
    rlc a                 ; Carry flag has bit to write 
    mov R0, a 
    mov MY_MOSI, c 
    setb MY_SCLK          ; Transmit 
    mov c, MY_MISO        ; Read received bit 
    mov a, R1             ; Save received bit in R1 
    rlc a 
    mov R1, a 
    clr MY_SCLK 
    djnz R2, DO_SPI_G_LOOP 
    ret

; so this is for displaying bcd
Left_blank mac
	mov a, %0
	anl a, #0xf0
	swap a
	jz Left_blank_%M_a
	ljmp %1
Left_blank_%M_a:
	Display_char(#' ')
	mov a, %0
	anl a, #0x0f
	jz Left_blank_%M_b
	ljmp %1
Left_blank_%M_b:
	Display_char(#' ')
endmac

; display # using bcd display, thus need to use bcd #
Display_10_digit_BCD:
	Set_Cursor(2, 7)
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	; Replace all the zeros to the left with blanks
	Set_Cursor(2, 7)
	Left_blank(bcd+4, skip_blank)
	Left_blank(bcd+3, skip_blank)
	Left_blank(bcd+2, skip_blank)
	Left_blank(bcd+1, skip_blank)
	mov a, bcd+0
	anl a, #0f0h
	swap a
	jnz skip_blank
	Display_char(#' ')
skip_blank:
	ret

; displaying # in 4 decimal
Display_formated_BCD:
	Set_Cursor(2, 7)
	Display_char(#' ')
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	ret

; waiting for p4.5 to press 
wait_for_P4_5:
	jb P4.5, $ ; loop while the button is not pressed
	Wait_Milli_Seconds(#50) ; debounce time
	jb P4.5, wait_for_P4_5 ; it was a bounce, try again
	jnb P4.5, $ ; loop while the button is pressed
	ret

; read an ADC channel like this 
; so result saved in R6, R7?
Read_ADC_Channel MAC
	mov b, #%0 
	lcall _Read_ADC_Channel 
ENDMAC
_Read_ADC_Channel: 
	clr CE_ADC 
	mov R0, #00000001B; Start bit:1 
	lcall DO_SPI_G 
	mov a, b 
	swap a 
	anl a, #0F0H 
	setb acc.7 ; Single mode (bit 7). 
	mov R0, a 
	lcall DO_SPI_G 
	mov a, R1 ; R1 contains bits 8 and 9 
	anl a, #00000011B  ; We need only the two least significant bits 
	mov R7, a ; Save result high. 
	mov R0, #55H; It doesn't matter what we transmit... 
	lcall DO_SPI_G 
	mov a, R1 
	mov R6, a ; R1 contains bits 0 to 7.  Save result low. 
	setb CE_ADC 
	ret

; pre-define string
Test_msg:  db 'Temp is:', 0
Next_line: db '\r', '\n', 0

; Send a character using the serial port
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret


; send bcd 
Send_BCD mac
    push ar0
    mov r0, %0
    lcall ?Send_BCD
    pop ar0
endmac
?Send_BCD:		
    push acc; Write most significant digit
    mov a, r0
    swap a
    anl a, #0fh
    orl a, #30h
    lcall putchar; write least significant digit
    mov a, r0
    anl a, #0fh
    orl a, #30h
    lcall putchar
    pop acc
    ret

; STRAT of the actual program
MyProgram:
	mov sp, #07FH ; Initialize the stack pointer
	; Configure P0 in bidirectional mode
    mov P0M0, #0
    mov P0M1, #0
    lcall LCD_4BIT
	Set_Cursor(1, 1)
    Send_Constant_String(#Test_msg)
forever:
    Read_ADC_Channel(0)
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)
    mov x+0, R6
	mov x+1, R7
	mov x+2, #0
	mov x+3, #0
	mov y+0, #low(410)
	mov y+1, #high(410)
	mov y+2, #0
	mov y+3, #0
    lcall mul32
    ;Load_y(10000)
    ;lcall mul32
    Load_y(1023)
    lcall div32 
    Load_y(273)
    lcall sub32
    Load_y(100)
    lcall mul32
    ;Send_BCD(bcd+1)
	lcall hex2bcd
	;lcall Display_formated_BCD
    lcall Display_10_digit_BCD
	;lcall wait_for_P4_5
	lcall InitSerialPort
	Send_BCD(bcd+1)
	mov DPTR, #Next_line
    lcall SendString

    ljmp forever
END
