	.global main

	.text
/* TODO: move all functions here */

	/* pad the buffer so that its length is 448 % 512 (56 mod 64 bytes)

	The length of the current buffer should be:
	%r9 + (%r10*8)

	The pad should be: 0x80 (first byte) + 0x00 until the buffer is 448 % 512
	Then append a 64-bit representation of the input length (should just be %r11)

	*/

__pad:
	
	shl 	$3,%r10
	add 	%r9,%r10
	/* %r10 now holds buffer length */
	

	/* set %r9 to number of bytes to pad */
	cmp 	$56,%r10
	jb	__pad_lt_64bytes

	/* this flag means that there are 2 bufs left to digest */
	mov	$2,%r12

	mov	$120,%r9
	sub	%r10,%r9
	dec	%r9
	movb	$0x80,-8(%rdi,%r10,1)
	
	jmp	__pad_writezeroes

	__pad_lt_64bytes:
		/* this flag means that this is the last buf to digest */
		mov 	$1,%r12
		movb 	$0x80,-8(%rdi,%r10,1)
		inc	%r10

	__pad_writezeroes:
		cmp 	$56,%r10
		je	__pad_complete
		movb	$0,-8(%rdi,%r10,1)
		inc	%r10
		jmp	__pad_writezeroes

	/* good enough */
	__pad_second_chunk:
		movq	$0,(%rdi)
		movq	$0,8(%rdi)
		movq	$0,16(%rdi)
		movq	$0,24(%rdi)
		movq	$0,32(%rdi)
		movq	$0,40(%rdi)
		movq	$0,48(%rdi)
		
	__pad_complete:
		/* endianness ?? */
		mov	%r11,56(%rdi)
		jmp	__md4_digest_round
		

	
	
	
main:

/* initialize registers */	

	mov 	(wordA),%eax
	mov	(wordB),%ebx
	mov	(wordC),%ecx
	mov	(wordD),%edx

	lea 	input, %rsi
	lea 	buf, %rdi

	mov	$0, %r9
	mov	$0, %r10
	mov	$0, %r11
	mov	$0, %r12

	/* EFFICIENCY: instead of loading 1 byte at a time
	load full register then test using %al and rsh'ing %rax

	PS: This could leave up to 7 bytes in the register which 
	are not	related to the input string, so align input buffer

	--REGISTERS--
	%rsi: 	source address
	%rdi:	destination buffer (64 bytes)
	%r8:	8 byte buffer for input string
	%r9:	which byte in the buffer register is being tested
	%r10:	how many buffer registers have been loaded -> if this is 8, then run the MD4 digest
	%r11:	total bytes tested (input string length can be calculated as the digest runs)

	TODO: Check endianness here, specifically with loading and shifting the buffer register
	--ALGORITHM-- 
	Check %r10, if it's 8 then we have processed 64 bytes and have to run a digest round

	Reset %r9 to zero
	Move 8 bytes from buffer to %r8
	Increment %r10

	Test byte in %r8b (LO byte)
	If it's zero, we've reached the end of the input string, so begin padding
	If it's not, increment %r9 and %r11
	
	Check if %r9 is 8 (have we processed all 8 bytes in the buffer reg?)
	If %r9 is 8, load a new chunk into the register
	Otherwise, shift the buffer register right by 8 bits (next byte in register)
	*/
	
  __loadbuf_new_chunk:
	cmp	$8,%r10
	je	__md4_digest_round
	mov	$0,%r9
	movq	(%rsi,%r10,8),%r8
	inc	%r10

  __loadbuf_loop_1:
	cmp	$0,%r8b
	je 	__pad

	/* using another register for this might be faster */	
	mov	%r10, %r15
	shl	$3,%r15
	add	%r9,%r15

	/* moving in 8-byte chunks here would definitely be faster */
	mov	%r8b,-8(%rdi,%r15,1)
	inc	%r9
	inc	%r11
	cmp	$8,%r9
	je 	__loadbuf_new_chunk
	shr	$8,%r8
	jmp	__loadbuf_loop_1

	
	
  __md4_digest_round:
	mov 	$0, %r10
	mov	$0, %r9	


/* save register states */
	push	%rax
	push	%rbx
	push	%rcx
	push	%rdx

/* From RFC 1320 */

        /* Round 1. */
        /* Let [abcd k s] denote the operation
             a = (a + F(b,c,d) + X[k]) <<< s. 
		<<< is logical shift? rotate? arithmetic shift?
		going with rotate
	*/
        /* Do the following 16 operations. */
	/*
        [ABCD  0  3]  [DABC  1  7]  [CDAB  2 11]  [BCDA  3 19]
        [ABCD  4  3]  [DABC  5  7]  [CDAB  6 11]  [BCDA  7 19]
        [ABCD  8  3]  [DABC  9  7]  [CDAB 10 11]  [BCDA 11 19]
        [ABCD 12  3]  [DABC 13  7]  [CDAB 14 11]  [BCDA 15 19]
	*/

	/* 
	%r13 = k 
	%r14 = s
	%r15 = temp register
	*/
  __pre_round_1:
	mov $0,%r13
	mov $3,%r14
	

  __round_1:

	/* a = a + F(b,c,d) */
	mov 	%eax,%r15d
	call 	__F
	add 	%r15d, %eax

	/* a = a + X[k] */
	movl 	(%rdi,%r13,4), %r15d
	add 	%r15d, %eax


	/* a = a <<< s */

	push	%rcx
	mov	%r14, %rcx
	rol 	%cl, %eax
	pop	%rcx

	add	$1,%r13
	add	$4,%r14
	cmp	$19,%r14
	jbe	r1_no_s_reset
	mov	$3,%r14
	
	r1_no_s_reset:
		cmp 	$16,%r13
		je	__pre_round_2
		call	__rotate_reg
		jmp	__round_1




/* Round 2. */
        /* Let [abcd k s] denote the operation
             a = (a + G(b,c,d) + X[k] + 5A827999) <<< s. */
 	/* Do the following 16 operations. */
	/*
        [ABCD  0  3]  [DABC  4  5]  [CDAB  8  9]  [BCDA 12 13]
        [ABCD  1  3]  [DABC  5  5]  [CDAB  9  9]  [BCDA 13 13]
        [ABCD  2  3]  [DABC  6  5]  [CDAB 10  9]  [BCDA 14 13]
        [ABCD  3  3]  [DABC  7  5]  [CDAB 11  9]  [BCDA 15 13]

	%r13 = k
	%r14 = s
	%r15 = temp register
	*/
	
  __pre_round_2:
	call 	__rotate_reg	
	mov 	$0,%r13
	mov	$3,%r14

  __round_2:
	/* a = a + G(b,c,d) */
	mov	%eax, %r15d
	call	__G
	add	%r15d,%eax

	/* a = a + X[k] + 0x5A827999 */
	movl	(%rdi,%r13,4),%r15d
	add	%r15d,%eax
	add	$0x5A827999,%eax

	/* a = a <<< s */
	push	%rcx
	mov	%r14, %rcx
	rol	%cl, %eax
	pop	%rcx


	cmp	$3,%r14
	je	r2_s_add_2
	add	$4,%r14
	jmp	r2_post_s_add
	
	r2_s_add_2:
	add	$2,%r14
	r2_post_s_add:
	add	$4,%r13
	
	/*
	cmp	$13,%r14
	jbe	r2_no_sk_reset
	sub	$11,%r13
	mov	$3,%r14
	
	cmp	$15,%r13
	ja	__pre_round_3
	r2_no_sk_reset:
	call	__rotate_reg
	jmp	__round_2
	*/

	cmp 	$13,%r14
	ja	r2_sk_reset

	r2_iter_restart:
		call 	__rotate_reg
		jmp	__round_2

	r2_sk_reset:
		cmp 	$15,%r13
		ja	__pre_round_3
		sub 	$11,%r13
		mov	$3,%r14
		jmp	r2_iter_restart

	/* Round 3. */
        /* Let [abcd k s] denote the operation
             a = (a + H(b,c,d) + X[k] + 6ED9EBA1) <<< s. */
        /* Do the following 16 operations. */
	/*
        [ABCD  0  3]  [DABC  8  9]  [CDAB  4 11]  [BCDA 12 15]
        [ABCD  2  3]  [DABC 10  9]  [CDAB  6 11]  [BCDA 14 15]
        [ABCD  1  3]  [DABC  9  9]  [CDAB  5 11]  [BCDA 13 15]
        [ABCD  3  3]  [DABC 11  9]  [CDAB  7 11]  [BCDA 15 15]

	%esi = k -> r13
	%edi = s -> r14
	%r15 = temp register
	*/
  __pre_round_3:
	call 	__rotate_reg
	mov	$0,%r13
	mov	$3,%r14

  __round_3:

	/* a = a + H(b,c,d) */
	mov	%eax,%r15d
	call	__H
	add	%r15d,%eax

	/* a = a + X[k] + 0x6ED9EBA1 */
	movl	(%rdi,%r13,4),%r15d
	add	%r15d,%eax
	add	$0x6ED9EBA1,%eax

	/* a = a <<< 3 */
	push	%rcx
	mov	%r14,%rcx
	rol	%cl,%eax
	pop	%rcx
	
	/* k (r13) pattern: add 8, sub 4, add 8, sub 10, add 8, sub 4, add 8, sub 13 */
	/* s (r14) pattern: add 6, add 2, add 4, reset to 3*/
	/* table:
	[k+8,s+6] [k-4,s+2] [k+8,s+4] [k-(10 or 13),s=3]
	if s=3, then k+=8 and s+=6
	if s=9, then k-=4 and s+=2
	if s=11, then k+=8 and s+=4
	if s=15, then k-=(10 or 13) and s=3

	1-4 cmps per round :(, TODO: optimize this part
	*/

	cmp	$3, %r14
	jne	r3_s_not_3
	add	$8,%r13
	add	$6,%r14
	jmp	r3_sk_inc_complete
	r3_s_not_3:

	cmp	$9, %r14
	jne	r3_s_not_9
	sub	$4,%r13
	add	$2,%r14
	jmp	r3_sk_inc_complete
	r3_s_not_9:
	
	cmp	$11, %r14
	jne	r3_s_not_11
	add	$8,%r13
	add	$4,%r14
	jmp	r3_sk_inc_complete
	r3_s_not_11:
	
	cmp	$14, %r13
	ja	r3_complete
	jne	r3_k_sub_10
	sub	$13, %r13
	mov	$3, %r14
	r3_k_sub_10:
	sub	$10, %r13
	mov	$3, %r14
	jmp	r3_sk_inc_complete

	r3_sk_inc_complete:
	call	__rotate_reg
	jmp	__round_3

	r3_complete:
	mov	%edx,%r15d
	pop	%rdx
	add	%r15d,%edx

	mov	%ecx,%r15d
	pop	%rcx
	add	%r15d,%ecx

	mov	%ebx,%r15d
	pop	%rbx
	add	%r15d,%ebx

	mov	%eax,%r15d
	pop	%rax
	add	%r15d,%eax

	cmp	$1,%r12
	je	__md4_process_complete
	ja	__pad_second_chunk
	jmp 	__loadbuf_new_chunk

  __md4_process_complete:
	mov	resA,%r8d
	mov	resB,%r9d
	mov	resC,%r10d
	mov	resD,%r11d

	cmp	%eax,%r8d
	jne	__md4_process_failed
	cmp	%ebx,%r9d
	jne	__md4_process_failed
	cmp	%ecx,%r10d
	jne	__md4_process_failed
	cmp	%edx,%r11d
	jne	__md4_process_failed

	lea	pass,%rsi
	mov	$15,%rdx
	call	__printmsg
	jmp	__md4_exit

	__md4_process_failed:

/* don't really have to repeat all this, but it's best practice */

	mov	%rcx,%r10
	mov	%rdx,%r11
	
	mov	%rax,%r15
	call	__reg_to_string
	lea	regstr,%rsi
	mov	$26,%rdx
	call	__printmsg


	mov	%rbx,%r15
	call	__reg_to_string
	lea	regstr,%rsi
	mov	$26,%rdx
	call	__printmsg

	mov	%r10,%r15
	call	__reg_to_string
	lea	regstr,%rsi
	mov	$26,%rdx
	call	__printmsg

	mov	%r11,%r15
	call	__reg_to_string
	lea	regstr,%rsi
	mov	$26,%rdx
	call	__printmsg



	__md4_exit:
		mov	$60,%rax
		mov	$0,%rdi
		syscall	

  __printmsg:

	mov	$1,%rax
	mov	$1,%rdi

	syscall

	ret
	
  __rotate_reg:
		
	mov	%edx, %r15d
	mov	%ecx, %edx
	mov	%ebx, %ecx
	mov	%eax, %ebx
	mov	%r15d, %eax

	ret

/* load regstr with a hex string with the value in r15 */
  __reg_to_string:
	push	%r14
	push	%r13
	push	%r12
	push	%rdi

	mov	$0,%r12
	lea	regstr,%rdi
	
	__rts_process_byte:
	mov	%r15b,%r14b
	mov	%r15b,%r13b

	and	$0xF0,%r14b
	SHR	$4,%r14b
	and	$0x0F,%r13b

	cmp	$9,%r13b
	ja	__bts_r13_hex
	add	$0x30,%r13b
	jmp	__bts_r14

	__bts_r13_hex:
	add	$0x37,%r13b

	__bts_r14:
	cmp	$9,%r14b
	ja	__bts_r14_hex
	add	$0x30,%r14b
	jmp	__bts_write

	__bts_r14_hex:
	add	$0x37,%r14b

	__bts_write:
	mov	%r14b,(%rdi,%r12,1)
	mov	%r13b,1(%rdi,%r12,1)
	movb	$0x20,2(%rdi,%r12,1)

	add	$3,%r12
	shr	$8,%r15

	cmp	$24,%r12
	jb	__rts_process_byte

	pop	%rdi
	pop	%r12
	pop	%r13
	pop	%r14

	ret
/*
--functions F,G,H will follow these conventions
ebx = X
ecx = Y
edx = Z
eax = return value

push rbx,rcx,rdx into stack so that the registers
dont get clobbered
*/


/*
F(X,Y,Z) = (X & Y) | (!X & Z)
*/

__F:
	push 	%rdx
	push	%rcx
	push	%rbx
	
	and	%ebx, %ecx
	andn	%ebx, %edx, %edx

	or	%edx, %ecx
	mov	%edx, %eax

	pop	%rbx
	pop	%rcx
	pop	%rdx
	ret


/*
G(X,Y,Z) = (X & Y) | (X & Z) | (Y & Z)
*/

__G:
	push	%rdx
	push	%rcx
	push	%rbx

	/* eax = X&Y */
	mov	%ebx, %eax
	and	%ecx, %eax

	/* ebx = X&Z */
	and	%edx, %ebx

	/* ecx = Y&Z */
	and	%edx, %ecx

	or	%ebx, %eax
	or	%ecx, %eax

	pop	%rbx
	pop	%rcx
	pop	%rdx
	ret


/*
H(X,Y,Z) = X ^ Y ^ Z
*/

__H:
	push 	%rdx
	push	%rcx
	push	%rbx

	xor	%ebx, %ecx
	xor	%ecx, %edx
	mov	%edx, %eax

	pop	%rbx
	pop	%rcx
	pop	%rdx
	
	ret


input:	.asciz 	"Hello world"
pass:	.asciz	"MD4 sum passed!"
fail:	.asciz	"MD4 sum failed."
resA:	.long	0x2f34e7ed
resB:	.long	0xc8180b87
resC:	.long	0x578159ff
resD:	.long	0x58e87c1a
wordA:	.long	0x01234567
wordB:	.long	0x89abcdef
wordC:	.long	0xfedcba98
wordD:	.long	0x76543210

	.bss
buf:	.fill	64
regstr:	.fill	24
.byte 0x0a

