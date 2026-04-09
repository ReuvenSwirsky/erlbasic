10 REM playmusic.bas - MML background music demo
20 REM Plays a short melody in background mode while printing lyrics.
30 REM Requires a WebSocket (browser) connection for audio.
40 REM
50 REM The tune is a simple arpeggio-style progression.
60 REM MB = background mode (music plays while program continues)
70 REM MF = foreground mode (program waits for each note before continuing)
80 REM MN/ML/MS = articulation: normal / legato / staccato
90 REM ON PLAY(n) GOSUB fires a handler when the queue drops below n notes.
100 REM
110 REM ----------------------------------------------------------
120 REM Part 1: foreground melody (program waits for each phrase)
130 REM ----------------------------------------------------------
140 PRINT "Playing intro (foreground mode)..."
150 PLAY "MF T160 L8 O4 C E G O5 C E G O5 C"
160 PLAY "MF T160 L8 O5 C G E O4 G E C O4 C"
170 PRINT ""
180 REM ----------------------------------------------------------
190 REM Part 2: background melody (program continues while music plays)
200 REM ----------------------------------------------------------
210 PRINT "Starting background music..."
220 PRINT ""
230 PLAY "MB T140 ML O4 L4 C E G O5 C L2 E"
240 PLAY "MB T140 ML O5 D B O4 G E L2 C"
250 PLAY "MB T140 ML O4 E G O5 C E L2 G"
260 PLAY "MB T140 ML O5 F D B O4 G L2 E"
270 REM Print while the music is playing
280 PRINT " *  D O - R E - M I  *"
290 SLEEP 0.4
300 PRINT "   Do, a deer, a female deer"
310 SLEEP 0.8
320 PRINT "   Re, a drop of golden sun"
330 SLEEP 0.8
340 PRINT "   Mi, a name I call myself"
350 SLEEP 0.8
360 PRINT "   Fa, a long long way to run"
370 SLEEP 0.8
380 PRINT ""
390 REM ----------------------------------------------------------
400 REM Part 3: ON PLAY(n) GOSUB - auto-refill the music queue
410 REM ----------------------------------------------------------
420 PRINT "Starting looped background with ON PLAY refill..."
430 PRINT "(Press Ctrl-C to stop)"
440 PRINT ""
450 LET PHRASE = 0
460 ON PLAY(4) GOSUB 1000
470 REM Seed the queue with the first two phrases
480 GOSUB 1000
490 GOSUB 1000
500 REM Main loop: just print while music plays
510 FOR I = 1 TO 20
520   LET N = PLAY(0)
530   PRINT "Queue: "; N; " notes remaining"
540   SLEEP 0.5
550 NEXT I
560 REM Done — switch back to foreground to let queue drain
570 PLAY "MF L1 P"
580 PRINT ""
590 PRINT "Done!"
600 END
1000 REM Subroutine: queue the next phrase of the melody
1010 LET PHRASE = PHRASE + 1
1020 IF PHRASE > 4 THEN PHRASE = 1
1030 IF PHRASE = 1 THEN PLAY "MB T160 L8 O4 C E G O5 C E G O5 C" : RETURN
1040 IF PHRASE = 2 THEN PLAY "MB T160 L8 O5 C G E O4 G E C C2." : RETURN
1050 IF PHRASE = 3 THEN PLAY "MB T160 L8 O4 E G O5 C E G O5 E C2." : RETURN
1060 IF PHRASE = 4 THEN PLAY "MB T160 L8 O5 D B O4 G E C G2." : RETURN
1070 RETURN
