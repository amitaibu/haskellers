{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Controller
    ( withHaskellers
    ) where

import Haskellers
import Settings
import Yesod.Helpers.Static
import Yesod.Helpers.Auth2
import Database.Persist.GenericSql
import Data.IORef
import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forever)
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set

-- Import all relevant handler modules here.
import Handler.Root
import Handler.Profile
import Handler.User
import Handler.Admin
import Handler.Email
import Handler.Skills
import Handler.Package
import Handler.Faq

-- This line actually creates our YesodSite instance. It is the second half
-- of the call to mkYesodData which occurs in Haskellers.hs. Please see
-- the comments there for more details.
mkYesodDispatch "Haskellers" resourcesHaskellers

-- Some default handlers that ship with the Yesod site template. You will
-- very rarely need to modify this.
getFaviconR :: Handler ()
getFaviconR = sendFile "image/x-icon" "favicon.ico"

getRobotsR :: Handler RepPlain
getRobotsR = return $ RepPlain $ toContent "User-agent: *"

-- This function allocates resources (such as a database connection pool),
-- performs initialization and creates a WAI application. This is also the
-- place to put your migrate statements to have automatic database
-- migrations handled by Yesod.
withHaskellers :: (Application -> IO a) -> IO a
withHaskellers f = Settings.withConnectionPool $ \p -> do
    flip runConnectionPool p $ runMigration $ do
        migrate (undefined :: User)
        migrate (undefined :: Ident)
        migrate (undefined :: Skill)
        migrate (undefined :: UserSkill)
        migrate (undefined :: Package)
        migrate (undefined :: Message)
    hprofs <- newIORef ([], 0)
    pprofs <- newIORef []
    _ <- forkIO $ fillProfs p hprofs pprofs
    let h = Haskellers s p hprofs pprofs
    toWaiApp h >>= f
  where
    s = fileLookupDir Settings.staticdir typeByExt

getHomepageProfs :: ConnectionPool -> IO [Profile]
getHomepageProfs pool = flip runConnectionPool pool $ do
    users <-
        selectList [ UserVerifiedEmailEq True
                   , UserVisibleEq True
                   , UserRealEq True
                   , UserBlockedEq False
                   -- FIXME , UserRealPicEq True
                   ] [] 0 0
    return $ mapMaybe userToProfile users

getPublicProfs :: ConnectionPool -> IO [Profile]
getPublicProfs pool = flip runConnectionPool pool $ do
    users <-
        selectList [ UserVerifiedEmailEq True
                   , UserVisibleEq True
                   , UserBlockedEq False
                   ]
                   [ UserRealDesc
                   , UserHaskellSinceAsc
                   , UserFullNameAsc
                   ] 0 0
    return $ mapMaybe userToProfile users

fillProfs :: ConnectionPool -> IORef ([Profile], Int) -> IORef [Profile]
          -> IO a
fillProfs pool hprofs pprofs = forever $ do
    hprofs' <- getHomepageProfs pool
    pprofs' <- getPublicProfs pool
    writeIORef hprofs (hprofs', length hprofs')
    writeIORef pprofs pprofs'
    threadDelay $ 1000 * 1000 * 60 * 5

userToProfile :: (UserId, User) -> Maybe Profile
userToProfile (uid, u) =
    case userEmail u of
        Nothing -> Nothing
        Just e -> Just Profile
            { profileUserId = uid
            , profileName = userFullName u
            , profileEmail = e
            , profileUser = u
            , profileSkills = Set.fromList [] -- FIXME
            }
