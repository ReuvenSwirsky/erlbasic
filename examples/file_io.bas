10 OPEN "tmp_fileio_seq.txt" FOR OUTPUT AS #1
20 WRITE #1, 123, "HELLO", 45
30 CLOSE #1
40 OPEN "tmp_fileio_seq.txt" FOR INPUT AS #1
50 INPUT #1, A, B$, C
60 PRINT A;",";B$;",";C
70 PRINT EOF(1)
80 CLOSE #1
90 OPEN "tmp_fileio_rec.dat" FOR RANDOM AS #2 LEN = 12
100 FIELD #2, 5 AS N$, 7 AS V$
110 N$ = "ALFA"
120 V$ = "123"
130 PUT #2, 1
140 N$ = "BETA"
150 V$ = "4567"
160 PUT #2, 2
170 N$ = ""
180 V$ = ""
190 GET #2, 2
200 PRINT LEFT$(N$,4);",";LEFT$(V$,4);",";LEN(N$);",";LEN(V$)
210 PRINT LOF(2)
220 CLOSE #2
230 END
