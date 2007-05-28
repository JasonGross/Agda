{-# OPTIONS -fglasgow-exts #-}

-- Generated by Alonzo

module Printf where
import RTS
import qualified RTP
import qualified PreludeShow
import qualified PreludeBool
import qualified RTN
import qualified AlonzoPrelude
import qualified PreludeList
import qualified RTP
import qualified PreludeNat
import qualified PreludeString
name1 = "Unit"
 
data T1 = C2
d1 = ()
name2 = "unit"
name3 = "Format"
 
data T3 a = C4
          | C5
          | C6
          | C7
          | C8
          | C9 a
          | C10 a
d3 = ()
name4 = "stringArg"
name5 = "natArg"
name6 = "intArg"
name7 = "floatArg"
name8 = "charArg"
name9 = "litChar"
name10 = "badFormat"
name12 = "BadFormat"
 
data T12 = C12
d12 v1 = ()
name14 = "format"
d14 = d14_1
  where d14_1 v0
          = cast (Printf.d18 (cast v0) (cast (PreludeString.d6 (cast v0))))
name18 = "format'"
d18 = d18_1
  where d18_1 v0
          (PreludeList.C6 (RTP.CharT '%')
             (PreludeList.C6 (RTP.CharT 's') v1))
          = cast
              (PreludeList.C6 (cast Printf.C4)
                 (cast (Printf.d18 (cast v0) (cast v1))))
        d18_1 a b = cast d18_2 a b
        d18_2 v0
          (PreludeList.C6 (RTP.CharT '%')
             (PreludeList.C6 (RTP.CharT 'n') v1))
          = cast
              (PreludeList.C6 (cast Printf.C5)
                 (cast (Printf.d18 (cast v0) (cast v1))))
        d18_2 a b = cast d18_3 a b
        d18_3 v0
          (PreludeList.C6 (RTP.CharT '%')
             (PreludeList.C6 (RTP.CharT 'd') v1))
          = cast
              (PreludeList.C6 (cast Printf.C6)
                 (cast (Printf.d18 (cast v0) (cast v1))))
        d18_3 a b = cast d18_4 a b
        d18_4 v0
          (PreludeList.C6 (RTP.CharT '%')
             (PreludeList.C6 (RTP.CharT 'f') v1))
          = cast
              (PreludeList.C6 (cast Printf.C7)
                 (cast (Printf.d18 (cast v0) (cast v1))))
        d18_4 a b = cast d18_5 a b
        d18_5 v0
          (PreludeList.C6 (RTP.CharT '%')
             (PreludeList.C6 (RTP.CharT 'c') v1))
          = cast
              (PreludeList.C6 (cast Printf.C8)
                 (cast (Printf.d18 (cast v0) (cast v1))))
        d18_5 a b = cast d18_6 a b
        d18_6 v0
          (PreludeList.C6 (RTP.CharT '%')
             (PreludeList.C6 (RTP.CharT '%') v1))
          = cast
              (PreludeList.C6 (cast (Printf.C9 (cast (RTP.CharT '%'))))
                 (cast (Printf.d18 (cast v0) (cast v1))))
        d18_6 a b = cast d18_7 a b
        d18_7 v0 (PreludeList.C6 (RTP.CharT '%') (PreludeList.C6 v1 v2))
          = cast
              (PreludeList.C6 (cast (Printf.C10 (cast v1)))
                 (cast (Printf.d18 (cast v0) (cast v2))))
        d18_7 a b = cast d18_8 a b
        d18_8 v0 (PreludeList.C6 v1 v2)
          = cast
              (PreludeList.C6 (cast (Printf.C9 (cast v1)))
                 (cast (Printf.d18 (cast v0) (cast v2))))
        d18_8 a b = cast d18_9 a b
        d18_9 v0 (PreludeList.C5) = cast PreludeList.C5
name29 = "Printf'"
d29 = d29_1
  where d29_1 (PreludeList.C6 (Printf.C4) v0)
          = cast
              (AlonzoPrelude.d41 (cast AlonzoPrelude.d3)
                 (cast (Printf.d29 (cast v0))))
        d29_1 a = cast d29_2 a
        d29_2 (PreludeList.C6 (Printf.C5) v0)
          = cast
              (AlonzoPrelude.d41 (cast RTN.d1) (cast (Printf.d29 (cast v0))))
        d29_2 a = cast d29_3 a
        d29_3 (PreludeList.C6 (Printf.C6) v0)
          = cast
              (AlonzoPrelude.d41 (cast AlonzoPrelude.d1)
                 (cast (Printf.d29 (cast v0))))
        d29_3 a = cast d29_4 a
        d29_4 (PreludeList.C6 (Printf.C7) v0)
          = cast
              (AlonzoPrelude.d41 (cast AlonzoPrelude.d2)
                 (cast (Printf.d29 (cast v0))))
        d29_4 a = cast d29_5 a
        d29_5 (PreludeList.C6 (Printf.C8) v0)
          = cast
              (AlonzoPrelude.d41 (cast AlonzoPrelude.d4)
                 (cast (Printf.d29 (cast v0))))
        d29_5 a = cast d29_6 a
        d29_6 (PreludeList.C6 (Printf.C10 v0) _)
          = cast (Printf.d12 (cast v0))
        d29_6 a = cast d29_7 a
        d29_7 (PreludeList.C6 (Printf.C9 _) v0)
          = cast (Printf.d29 (cast v0))
        d29_7 a = cast d29_8 a
        d29_8 (PreludeList.C5) = cast Printf.d1
name38 = "Printf"
d38 = d38_1
  where d38_1 v0 = cast (Printf.d29 (cast (Printf.d14 (cast v0))))
name41 = "printf"
d41 = d41_1
  where d41_1 v0
          = cast (Printf.d46 (cast v0) (cast (Printf.d14 (cast v0))))
name46 = "printf'"
d46 = d46_1
  where d46_1 v0 (PreludeList.C6 (Printf.C4) v1)
          (AlonzoPrelude.C44 v2 v3)
          = cast
              (PreludeString.d4 (cast v2)
                 (cast (Printf.d46 (cast v0) (cast v1) (cast v3))))
        d46_1 a b c = cast d46_2 a b c
        d46_2 v0 (PreludeList.C6 (Printf.C5) v1) (AlonzoPrelude.C44 v2 v3)
          = cast
              (PreludeString.d4 (cast (PreludeShow.d3 (cast v2)))
                 (cast (Printf.d46 (cast v0) (cast v1) (cast v3))))
        d46_2 a b c = cast d46_3 a b c
        d46_3 v0 (PreludeList.C6 (Printf.C6) v1) (AlonzoPrelude.C44 v2 v3)
          = cast
              (PreludeString.d4 (cast (PreludeShow.d2 (cast v2)))
                 (cast (Printf.d46 (cast v0) (cast v1) (cast v3))))
        d46_3 a b c = cast d46_4 a b c
        d46_4 v0 (PreludeList.C6 (Printf.C7) v1) (AlonzoPrelude.C44 v2 v3)
          = cast
              (PreludeString.d4 (cast (PreludeShow.d8 (cast v2)))
                 (cast (Printf.d46 (cast v0) (cast v1) (cast v3))))
        d46_4 a b c = cast d46_5 a b c
        d46_5 v0 (PreludeList.C6 (Printf.C8) v1) (AlonzoPrelude.C44 v2 v3)
          = cast
              (PreludeString.d4 (cast (PreludeShow.d5 (cast v2)))
                 (cast (Printf.d46 (cast v0) (cast v1) (cast v3))))
        d46_5 a b c = cast d46_6 a b c
        d46_6 v0 (PreludeList.C6 (Printf.C9 v1) v2) v3
          = cast
              (PreludeString.d4
                 (cast
                    (PreludeString.d7
                       (cast (PreludeList.C6 (cast v1) (cast PreludeList.C5)))))
                 (cast (Printf.d46 (cast v0) (cast v2) (cast v3))))
        d46_6 a b c = cast d46_7 a b c
        d46_7 _ (PreludeList.C6 (Printf.C10 _) _) _ = undefined
        d46_7 a b c = cast d46_8 a b c
        d46_8 v0 (PreludeList.C5) (Printf.C2) = cast ("")
name66 = "mainS"
d66 = d66_1
  where d66_1
          = cast
              (Printf.d41 (cast ("Answer is %n, pi = %f %% %s"))
                 (cast
                    (AlonzoPrelude.C44 (cast (RTP._primIntToNat (42 :: Prelude.Int)))
                       (cast
                          (AlonzoPrelude.C44 (cast (3.14159 :: Prelude.Double))
                             (cast (AlonzoPrelude.C44 (cast ("Alonzo")) (cast Printf.C2))))))))
main = putStrLn d66
