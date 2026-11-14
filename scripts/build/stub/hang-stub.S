// Hang variant of the minimal arm64 "kernel" for the Razer Edge (nicole) bring-up: proves whether ABL
// really hands off to our image. It only calls PSCI SYSTEM_OFF (SMC, then HVC).
//   device powers off            -> ABL jumped to our code; the crash is in our kernel/DTB
//   device resets back to Android -> ABL itself fails inside BootLinux
// If neither conduit works it parks the CPU (screen keeps the logo; manual reset).
	.section .text
	.global _head
_head:
	b	start			// code0
	.long	0			// code1
	.quad	0			// text_offset
	.quad	image_end - _head	// image_size
	.quad	0xa			// flags: little endian, 4K pages, anywhere in RAM
	.quad	0, 0, 0			// res2..res4
	.ascii	"ARM\x64"		// magic
	.long	0			// res5
start:
1:	wfe
	b	1b
	movz	x0, #0x0008
	movk	x0, #0x8400, lsl #16	// PSCI 0.2 SYSTEM_OFF = 0x84000008
	smc	#0
	movz	x0, #0x0008
	movk	x0, #0x8400, lsl #16
	hvc	#0
1:	wfe
	b	1b
	.balign	4096
image_end:
