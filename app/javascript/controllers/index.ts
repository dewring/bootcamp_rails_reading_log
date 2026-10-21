// Register each Stimulus controller manually — esbuild has no importmap-style eager loading
import { application } from "./application"
import SearchController from "./search_controller"
import ProgressBarController from "./progress_bar_controller"
import QuickAddController from "./quick_add_controller"
import IsbnScannerController from "./isbn_scanner_controller"
import NavbarController from "./navbar_controller"
import NotificationDropdownController from "./notification_dropdown_controller"
import NavDropdownController from "./nav_dropdown_controller"
import SubmitOnChangeController from "./submit_on_change_controller"
import ReviewComposerController from "./review_composer_controller"
import MyLogCarouselController from "./my_log_carousel_controller"
import SelectDropdownController from "./select_dropdown_controller"
import ClubBookSearchController from "./club_book_search_controller"
import FlashNotificationsController from "./flash_notifications_controller"
import ClubRepliesController from "./club_replies_controller"
import ClubMessageController from "./club_message_controller"
import ClubDiscussionController from "./club_discussion_controller"

application.register("search", SearchController)
application.register("progress-bar", ProgressBarController)
application.register("quick-add", QuickAddController)
application.register("isbn-scanner", IsbnScannerController)
application.register("navbar", NavbarController)
application.register("nav-menu", NavDropdownController)
application.register("notification-dropdown", NotificationDropdownController)
application.register("account-dropdown", NavDropdownController)
application.register("submit-on-change", SubmitOnChangeController)
application.register("review-composer", ReviewComposerController)
application.register("my-log-carousel", MyLogCarouselController)
application.register("select-dropdown", SelectDropdownController)
application.register("club-book-search", ClubBookSearchController)
application.register("flash-notifications", FlashNotificationsController)
application.register("club-discussion", ClubDiscussionController)

application.register("club-replies", ClubRepliesController)

application.register("club-message", ClubMessageController)
