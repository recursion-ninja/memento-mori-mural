{-# LANGUAGE CPP #-}

module Main where

import Control.Monad.Trans.State.Strict
import Data.Foldable
#if __GLASGOW_HASKELL__ < 861
import Data.Semigroup ((<>))
#endif
import Data.Time
import Data.Time.Calendar.OrdinalDate
import System.Environment
import Text.Read (readMaybe)


data  YearAlive
    = LeapWeekYear
    | FullYear
    | Partial Word


main :: IO ()
main = do
    args <- parseArgs <$> getArgs
    case args of
      Left err -> putStrLn err
      Right (birthDay, lifeExpectancy) -> do
          today <- getCurrentTime
          let daysAlive = getDaysAlive birthDay today
          putStrLn ""
          putStr $ renderLifetimeMural birthDay lifeExpectancy today
          putStr $ renderBenediction daysAlive
          putStrLn ""
          pure ()


renderBenediction :: Show a => a -> String
renderBenediction daysAlive = unlines
    [ "    \ESC[1;37m .-. \ESC[39;49;0m  "
    , "    \ESC[1;37m(0.0)\ESC[39;49;0m  " <> "Days survived: \ESC[3m" <> show daysAlive <> "\ESC[0m"
    , "    \ESC[1;37m |m| \ESC[39;49;0m  " <> "\ESC[1mMemento Mori\ESC[0m"
    ]


parseArgs :: [String] -> Either String (Day, Word)
parseArgs args =
  let expectedMsg = "Expected birthday in format YYYY-MM-DD"
  in  case args of
        [] -> Left expectedMsg
        x:xs ->
          case utctDay <$> readMaybe (x <> " 00:00:00.000000000 UTC") of
            Nothing  -> Left $ fold ["Could not parse birthday: ", x, "\n", expectedMsg]
            Just day ->
              case xs of
                [] -> Right (day, 75)
                y:_ ->
                  case (readMaybe y :: Maybe Int) of
                    Nothing -> Left $ fold ["Could not parse life expectancy: ", y, "\nExpected a number"]
                    Just n | n < 1 -> Left $ fold ["Could not accept life expectancy: ", y, "\nExpected a positive number"]
                    Just n  -> Right (day, toEnum n)


getDaysAlive :: Day -> UTCTime -> Word
getDaysAlive bDay = fromInteger . flip diffDays bDay . utctDay


getBirthYear :: Day -> Word
getBirthYear = fromIntegral . fst . toOrdinalDate


getWeeksAlive :: Day -> Word -> Word -> [YearAlive]
getWeeksAlive birthDay lifeExpectancy daysAlive = firstYear : go firstDays 1
  where
    (firstWeeks, firstDays) = daysSinceBirthdayOnStartOfYear birthDay 1 `quotRem` 7
    firstYear = Partial firstWeeks

    go         _ yearCount | yearCount > lifeExpectancy = []
    go extraDays yearCount
      | daysElapsed >= daysAlive = [Partial finalWeeks]
      | surplusDays >= 7         = LeapWeekYear : go (surplusDays - 7) (yearCount + 1)
      | otherwise                =     FullYear : go  surplusDays      (yearCount + 1)
      where
        daysElapsed = daysSinceBirthdayOnStartOfYear birthDay yearCount
        (_, extra)  = daysElapsed `quotRem` 7
        surplusDays = extraDays + extra
        finalDays   = daysAlive - daysSinceBirthdayOnStartOfYear birthDay (yearCount - 1)
        finalWeeks  = finalDays `quot` 7


daysSinceBirthdayOnStartOfYear :: Day -> Word -> Word
daysSinceBirthdayOnStartOfYear birthDay yearAfter = daysElapsed
   where
     birthYear   = getBirthYear birthDay
     targetYear  = fromOrdinalDate (fromIntegral (birthYear + yearAfter)) 0
     daysElapsed = fromIntegral (diffDays targetYear birthDay) - 1
                        

renderLifetimeMural :: Day -> Word -> UTCTime -> String
renderLifetimeMural birthDay lifeExpectancy today = unlines . fmap pad . lines $ fold
    [ header birthDay lifeExpectancy
    , body   birthDay lifeExpectancy weeksAlive
    , footer birthDay lifeExpectancy
    ]
  where
    daysAlive  = getDaysAlive  birthDay today
    weeksAlive = getWeeksAlive birthDay lifeExpectancy daysAlive
    pad = ("  " <>)

body :: Day -> Word -> [YearAlive] -> String
body birthDay lifeExpectancy yearsAlive = unlines [ rowGen r | r <- [0..6] ]
  where
    pref        = bodyPrefix birthDay
    defaultLine = fullWidthLine birthDay lifeExpectancy '┃' '│' ' ' '┃'

    rowGen r = begin <> close
      where
        close = drop (length begin) defaultLine
        begin = pref <> lived
        lived = f r <$> yearsAlive

    f row LeapWeekYear | row == 0 = '▅'
    f row FullYear     | row == 0 = '▄'
    f row (Partial w) =
        let (q,r) = w `quotRem` 8
        in  case q `compare` (6-row) of
              LT -> ' '
              GT -> '█'
              EQ ->
                case r of
                  1 -> '▁'
                  2 -> '▂'
                  3 -> '▃'
                  4 -> '▄'
                  5 -> '▅'
                  6 -> '▆'
                  7 -> '▇'
                  _ -> ' '
    f _ _ = '█'


header :: Day -> Word -> String
header birthDay lifeExpectancy =
    fullWidthLine birthDay lifeExpectancy '┏' '┯' '━' '┓' <> "\n"


bodyPrefix :: Day -> String
bodyPrefix birthDay = "┃" <> suffix
  where
    birthYear = getBirthYear birthDay
    startYear = getStartYear birthDay
    diffYears = birthYear - startYear 
    suffix =
      case diffYears of
        0 -> ""
        1 -> "│"
        e -> '│' : replicate (fromEnum e - 1) ' '


footer :: Day -> Word -> String
footer birthDay lifeExpectancy = unlines
    [ fullWidthLine birthDay lifeExpectancy '┗' '┷' '━' '┛'
    , footerYears birthDay lifeExpectancy
    ]


fullWidthLine :: Day -> Word -> Char -> Char -> Char -> Char -> String 
fullWidthLine birthDay lifeExpectancy s f a e =
    s : ((`evalState` (0::Word)) . traverse (const every5) . tail $ init line) <> [e]
  where
    line   = footerYears birthDay lifeExpectancy
    every5 = do
        v <- get
        put  $ if v == 4 then 0 else v + 1
        pure $ if v == 0 then f else a


footerYears :: Day -> Word -> String 
footerYears birthDay lifeExpectancy = shownYears
  where
    birthYear  = getBirthYear birthDay
    startYear  = getStartYear birthDay
    finalYear  = startYear + lifeExpectancy + offset
    offset | birthYear == startYear = 0
           | otherwise = 5
    shownYears = unwords $ show <$> [startYear, startYear+5 .. finalYear]


getStartYear :: Day -> Word
getStartYear birthDay = startYear
  where
    birthYear  = getBirthYear birthDay
    startYear  = birthYear - (birthYear `mod` 5)
