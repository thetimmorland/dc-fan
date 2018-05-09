;
; dc-fan.asm
;
; Created: 2018-04-11 1:39:30 PM
; Author : Tim
;
; Controls a 4-Wire PWM Fan. Sends data about fan settings over UART.
;

;
; MACROS
;

#define F_CPU 16000000

; pulse width modulation
#define F_PWM 25000
#define PWM_PRESCALE 8
#define	PWM_TOP int(F_CPU / PWM_PRESCALE / F_PWM)


; serial communication
#define USART_BAUD 9600
#define USART_UBRR int(F_CPU / 16 / USART_BAUD - 1)

;
; General Data Registers
;

.def count = r2
.def freq = r3

;
; INTERRUPT VECTOR TABLE
;

.org 0x0000
rjmp reset

.org ADCCaddr
rjmp ADC_Complete

.org OVF0addr
rjmp TIM0_OVF

.org OVF1addr
rjmp TIM1_OVF

.org ICP1addr
rjmp TIM1_IC

.org INT_VECTORS_SIZE

;
; INTERUPT HANDLERS
;

ADC_Complete:
	push r16
	push r17

	; setup for map
	lds r16, ADCH
	ldi r17, PWM_TOP

	; start map of ADC byte to value from 1-80 through multiplcation
	mul r16, r17

	; finish map by storing only high byte to divide by 256 (equivilent to val >> 8)
	sts OCR2B, r1

	pop r17
	pop r16

	reti

TIM0_OVF:
	; DO NOT DELETE! this empty interupt clears TIM0_OVF flag to re-trigger adc
	reti

TIM1_OVF:
	; divide count by two to account for fan giving two signals per cycle
	lsr count
	mov freq, count
	clr count

	reti

TIM1_IC:
	; record input capture
	inc count
	reti

;
; MAIN PROGRAM
;

reset:
	rcall IO_Init
	rcall TIM0_Init
	rcall TIM1_Init
	rcall TIM2_Init
	rcall ADC_Init
	rcall USART_Init

	sei

loop:
	; send adc reading
	lds r25, ADCH
	rcall USART_Transmit

	; send fan frequency
	mov r25, freq
	rcall USART_Transmit

	rjmp loop


;
; INIT
;

IO_Init:
	; enable output for OC2B
	ldi r16, (1<<PORTD3)
		out DDRD, r16

	ret

TIM0_Init:
	; prescale clk/1028
	ldi r16, (1<<CS02)|(1<<CS00)
		out TCCR0B, r16

	; enable overflow interupt
	ldi r16, (1<<TOIE0)
		sts TIMSK0, r16

	ret

TIM1_Init:
	
	; prescale clk/256
	ldi r16, (1<<CS12)
		sts TCCR1B, r16

	; enable input capture and overflow interupt
	ldi r16, (1<<ICIE1)|(1<<TOIE1)
		sts TIMSK1, r16

	ret

TIM2_Init:
	; OC2A disconnected
	; Toggle OC2B on compare match
	; fast PWM
	; top = OCR2A
	ldi r16, (1<<COM2B1)|(1<<WGM21)|(1<<WGM20)
		sts TCCR2A, r16

	; fast PWM
	; top = OCR2A
	; prescale clk/8
	ldi r16, (1<<WGM22)|(1<<CS21)
		sts TCCR2B, r16

	; set pwm freqency to 25000kHz
	ldi r16, PWM_TOP
		sts OCR2A, r16
	
	ret

ADC_Init:
	; disable digital io on all analog pins
	ser r16
		sts DIDR0, r16

	; AVCC reference voltage, left adjust result
	ldi r16, (1<<REFS0)|(1<<ADLAR)
		sts ADMUX, r16

	; enable ADC, start conversion, enable automatic triggering, enable interrupt, prescale clk/128
	ldi r16, (1<<ADEN)|(1<<ADSC)|(1<<ADATE)|(1<<ADIE)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)
		sts ADCSRA, r16

	; trigger ADC on timer0 overflow
	ldi r16, (1<<ADTS2)
		sts ADCSRB, r16

	ret

USART_Init:
	; load baud rate
	ldi r17, HIGH(USART_UBRR)
	ldi r16, LOW(USART_UBRR)

	; set baud rate to UBRR0
	sts UBRR0H, r17
	sts UBRR0L, r16

	; enable receiver and transmitter
	ldi r16, (1<<TXEN0)
		sts UCSR0B, r16

	; set frame format: 8data, 1 stop bit
	ldi r16, (3<<UCSZ00)
		sts UCSR0C, r16

	ret

;
; SUBROUTINES
;

USART_Transmit:
	lds r16, UCSR0A
	sbrs r16, UDRE0
		rjmp USART_Transmit

	; Put data into buffer, sends the data
	sts UDR0, r25

	ret