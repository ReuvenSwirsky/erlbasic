10 REM Simplified test version
20 LET W = 60
30 LET H = 20
40 DIM GRID(60, 20)
50 REM Initialize
60 FOR Y = 1 TO H
70   FOR X = 1 TO W
80     IF RND(1) < 0.3 THEN GRID(X, Y) = 1 ELSE GRID(X, Y) = 0
90   NEXT X
100 NEXT Y
110 REM
120 PRINT "Initialized"
130 CLS
140 REM Draw once
150 COLOR 10
160 LOCATE 1, 1
170 PRINT "Generation: 1"
180 PRINT "About to draw Y=1"
190 LOCATE 2, 1
200 PRINT "After LOCATE 2,1"
210 REM Try drawing just first row
220 FOR X = 1 TO 5
230   PRINT X; " ";
240 NEXT X
250 PRINT
260 PRINT "Drew first 5 positions"
270 END
