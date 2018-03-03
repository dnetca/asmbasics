	.global _start

	.text

_start:
	mov 	input, %esi
	mov 	buf, %edi
	mov	(%esi,%edx,1),%al
	cmp	$0,%al
	je	__pad
	mov	%al,(%edi,%edx,1)
	add	$1,%edx
  __afterpad:
	call	__strlen
	movl	$0,(%ecx,%edx,1)
	add	$4,%edx
	movl	%eax,(%ecx,%edx,1)

/* initialize registers */	
	mov 	(wordA),%eax
	mov	(wordB),%ebx
	mov	(wordC),%ecx
	mov	(wordD),%edx

/* save previous register states */
	push	%eax
	push	%ebx
	push	%ecx
	push	%edx

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
	%esi = k 
	%edi = s
	*/
	
	mov	$0, %esi
  __round_1:
		push 	%edi
		mov 	%eax,%edi
		call 	__F
		add 	%edi, %eax
		lea	buf,%edi
		mov 	(%edi,%esi,1), %edi
		add 	%edi, %eax
		pop	%edi
		rol 	%eax, %edi

		add	$1,%esi
		add	$4,%edi

		cmp	$19,%edi
		jbe	r1_no_s_reset
		mov	$3,%edi
		r1_no_s_reset:

		cmp 	$16,%esi
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

	esi = k
	edi = s
	*/
	
  __pre_round_2:
	call 	__rotate_reg	
	mov 	$0,%esi
	mov	$3,%edi
  __round_2:
	push	%edi
	mov	%eax, %edi
	call	__G
	add	%edi,%eax
	lea	buf,%edi
	mov	(%edi,%esi,1),%edi
	add	%edi,%eax
	add	$0x5A827999,%eax
	pop	%edi
	rol	%eax, %edi

	cmp	$3,%edi
	jne	r2_s_add_4
	add	$2,%edi
	jmp	r2_post_s_add
	
	r2_s_add_4:
	add	$4,%edi
	r2_post_s_add:
	add	$4,%esi
	
	
	cmp	$13,%edi
	jbe	r2_no_sk_reset
	sub	$11,%esi
	mov	$3,%edi
	
	cmp	$15,%esi
	ja	__pre_round_3
	r2_no_sk_reset:
	call	__rotate_reg
	jmp	__round_2


	/* Round 3. */
        /* Let [abcd k s] denote the operation
             a = (a + H(b,c,d) + X[k] + 6ED9EBA1) <<< s. */
        /* Do the following 16 operations. */
	/*
        [ABCD  0  3]  [DABC  8  9]  [CDAB  4 11]  [BCDA 12 15]
        [ABCD  2  3]  [DABC 10  9]  [CDAB  6 11]  [BCDA 14 15]
        [ABCD  1  3]  [DABC  9  9]  [CDAB  5 11]  [BCDA 13 15]
        [ABCD  3  3]  [DABC 11  9]  [CDAB  7 11]  [BCDA 15 15]

	esi = k
	edi = s
	*/
  __pre_round_3:
	call __rotate_reg
	mov	$0,%esi
	mov	$3,%edi

  __round_3:
	push 	%edi
	mov	%eax,%edi
	call	__H
	add	%edi,%eax
	lea	buf,%edi
	mov	(%edi,%esi,1),%edi
	add	%edi,%eax
	add	$0x6ED9EBA1,%eax
	pop	%edi
	rol	%eax,%edi

	
	/* k (esi) pattern: add 8, sub 4, add 8, sub 10, add 8, sub 4, add 8, sub 13 */
	/* s (edi) pattern: add 6, add 2, add 4, reset to 3*/
	/* table:
	[k+8,s+6] [k-4,s+2] [k+8,s+4] [k-(10 or 13),s=3]
	if s=3, then k+=8 and s+=6
	if s=9, then k-=4 and s+=2
	if s=11, then k+=8 and s+=4
	if s=15, then k-=(10 or 13) and s=3

	1-4 cmps per round :(, TODO: optimize this part
	*/

	cmp	$3, %edi
	jne	r3_s_not_3
	add	$8,%esi
	add	$6,%edi
	jmp	r3_sk_inc_complete
	r3_s_not_3:

	cmp	$9, %edi
	jne	r3_s_not_9
	sub	$4,%esi
	add	$2,%edi
	jmp	r3_sk_inc_complete
	r3_s_not_9:
	
	cmp	$11, %edi
	jne	r3_s_not_11
	add	$8,%esi
	add	$4,%edi
	jmp	r3_sk_inc_complete
	r3_s_not_11:
	
	cmp	$14, %esi
	ja	r3_complete
	jne	r3_k_sub_10
	sub	$13, %esi
	mov	$3, %edi
	r3_k_sub_10:
	sub	$10, %esi
	mov	$3, %edi
	jmp	r3_sk_inc_complete

	r3_sk_inc_complete:
	call	__rotate_regs
	jmp	__round_3

	r3_complete:
	mov	%edx,%edi
	pop	%edx
	add	%edi,%edx

	mov	%ecx,%edi
	pop	%ecx
	add	%edi,%ecx

	mov	%ebx,%edi
	pop	%ebx
	add	%edi,%ebx

	mov	%eax,%edi
	pop	%eax
	add	%edi,%eax

  __pad:
	mov 	$0x80,%al
	mov	%al,(%ecx,%edx,1)


	add	$1,%edx
	cmp	$56,%edx
	je	__afterpad
    __pad_zeroloop:
	mov	$0,%al
	mov	%al,(%ecx,%edx,1)
	add	$1,%edx
	cmp	$56,%edx
	jne	__pad_zeroloop
	jmp	__afterpad
	
  __rotate_reg:
		
	mov	%edx, %edi
	mov	%ecx, %edx
	mov	%ebx, %ecx
	mov	%eax, %ebx
	mov	%edi, %eax

	ret

/*
strlen will return the length in eax
and will take the string pointer in ebx
*/

__strlen:
	mov 	$0, %eax
	mov 	$0, %ch

  __strlen_count_loop:
	mov 	(%ebx,%eax,1),%cl
	add 	$1, %eax

	cmp 	%cl, %ch
	jne 	__strlen_count_loop
	
	sub 	$1, eax
	ret
/*
--functions F,G,H will follow these conventions
ebx = X
ecx = Y
edx = Z
eax = return value
*/

/*
F(X,Y,Z) = (X & Y) | (!X & Z)
*/

__F:
	/* make sure we don't clobber the registers... */
	push 	%edx
	push	%ecx
	push	%ebx
	
	and	%ebx, %ecx, %ecx
	andn	%edx, %ebx, %edx

	or	%edx, %ecx
	mov	%edx, %eax

	pop	%ebx
	pop	%ecx
	pop	%edx
	ret


/*
G(X,Y,Z) = (X & Y) | (X & Z) | (Y & Z)
*/

__G:
	push	%edx
	push	%ecx
	push	%ebx

	and	%eax, %ebx, %ecx
	and	%ebx, %ebx, %edx
	and	%ecx, %ecx, %edx

	or	%eax, %eax, %ebx
	or	%eax, %eax, %ecx

	pop	%ebx
	pop	%ecx
	pop	%edx
	ret


/*
H(X,Y,Z) = X ^ Y ^ Z
*/

__H:

	xor	%eax, %ebx, %ecx
	xor	%eax, %eax, %edx
	
	ret


	.data

input:	.asciz 	"Hello world"
resA:	.quad	0x2f34e7ed
resB:	.quad	0xc8180b87
resC:	.quad	0x578159ff
resD:	.quad	0x58e87c1a
buf:	.fill	64

wordA:	.quad	0x01234567
wordB:	.quad	0x89abcdef
wordC:	.quad	0xfedcba98
wordD:	.quad	0x76543210
