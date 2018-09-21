{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE DeriveLift          #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE TemplateHaskell     #-}
module Etc.Internal.Spec.Types where

import           RIO
import qualified RIO.HashMap as HashMap
import qualified RIO.Map     as Map
import qualified RIO.Text    as Text

import qualified Data.Aeson.BetterErrors as JSON
import Language.Haskell.TH.Syntax (Lift (..))

import qualified Data.Aeson              as JSON

newtype SpecError err = SpecError err

data SpecParserError
  = CannotInferTypeFromDefault ![Text] !JSON.Value
  | InferredNestedArrayOnDefault ![Text] !JSON.Value
  | UnknownConfigValueType ![Text] !Text
  | DefaultValueTypeMismatchFound ![Text] !ConfigValueType !JSON.Value
  | RedundantKeysOnValueSpec ![Text] ![Text]
  | InvalidSpecEntries !ConfigValue
  deriving (Show)

instance Exception SpecParserError

newtype CustomType
  = CustomType {customTypeParser :: JSON.Parse () () }

-- |
data SingleConfigValueType
  = CVTString
  | CVTNumber
  | CVTBool
  | CVTObject
  | CVTCustom Text
  deriving (Generic, Show, Read, Eq)

instance Lift SingleConfigValueType where
  lift cvType =
    case cvType of
      CVTString -> [| CVTString |]
      CVTNumber -> [| CVTNumber |]
      CVTBool ->   [| CVTBool   |]
      CVTObject -> [| CVTObject |]
      CVTCustom txt ->
        let
          str = Text.unpack txt
        in
          [| CVTCustom (Text.pack str) |]

-- |
data ConfigValueType
  = CVTSingle !SingleConfigValueType
  | CVTArray  !SingleConfigValueType
  deriving (Generic, Show, Read, Eq, Lift)



stripArrayWrapper :: ConfigValueType -> SingleConfigValueType
stripArrayWrapper (CVTArray inner) = inner
stripArrayWrapper (CVTSingle inner) = inner

isCVTArray :: ConfigValueType -> Bool
isCVTArray (CVTArray {}) = True
isCVTArray _ = False

-- |
data ConfigValueData =
  ConfigValueData {
    configValueDefault   :: !(Maybe JSON.Value)
  , configValueType      :: !ConfigValueType
  , configValueSensitive :: !Bool
  , configValueJSON      :: !JSON.Value
  }
  deriving (Generic, Show, Eq, Lift)

-- |
data ConfigValue
  = ConfigValue !ConfigValueData
  | SubConfig   !(Map Text ConfigValue)
  deriving (Generic, Show, Eq)

instance Lift ConfigValue where
  lift val =
    case val of
      ConfigValue configVal -> [|ConfigValue configVal|]
      SubConfig subConfig ->
        let subConfigList = map (first Text.unpack) $ Map.toList subConfig
         in [|SubConfig $ Map.fromList $ map (first Text.pack) subConfigList|]

-- |
data ConfigSpec
  = ConfigSpec { configSpecJSON    :: !JSON.Object
               , configSpecEntries :: !(Map Text ConfigValue)
               }
  deriving (Generic, Show, Eq)

instance Lift ConfigSpec where
  lift (ConfigSpec specJson specEntries) =
    let specJsonList = map (first Text.unpack) $ HashMap.toList specJson
        entriesList = map (first Text.unpack) $ Map.toList specEntries
     in [|ConfigSpec
            { configSpecJSON =
                HashMap.fromList $ map (first Text.pack) specJsonList
            , configSpecEntries =
                Map.fromList $ map (first Text.pack) entriesList
            }|]

getConfigSpecJSON :: ConfigSpec -> JSON.Object
getConfigSpecJSON = configSpecJSON

getConfigSpecEntries :: ConfigSpec -> ConfigValue
getConfigSpecEntries = SubConfig . configSpecEntries

blankConfigValueJSON :: ConfigSpec -> ConfigSpec
blankConfigValueJSON spec@ConfigSpec { configSpecEntries } = spec
  { configSpecEntries = Map.map blankValue configSpecEntries
  }
 where
  blankValue val = case val of
    ConfigValue valueData -> ConfigValue (valueData { configValueJSON = JSON.object [] })
    SubConfig   subConfig -> SubConfig $ Map.map blankValue subConfig
