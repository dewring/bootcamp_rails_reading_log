// Register each Stimulus controller manually — esbuild has no importmap-style eager loading
import { application } from "./application"
import SearchController from "./search_controller"
import ProgressBarController from "./progress_bar_controller"
import QuickAddController from "./quick_add_controller"
import IsbnScannerController from "./isbn_scanner_controller"
import NavbarController from "./navbar_controller"
import NavMenuController from "./nav_menu_controller"
import NotificationDropdownController from "./notification_dropdown_controller"
import AccountDropdownController from "./account_dropdown_controller"
import BookPickerController from "./book_picker_controller"
import SubmitOnChangeController from "./submit_on_change_controller"
import ReviewComposerController from "./review_composer_controller"
import MyLogCarouselController from "./my_log_carousel_controller"
import ProfilePhotoController from "./profile_photo_controller"
import SelectDropdownController from "./select_dropdown_controller"
import ClubBookSearchController from "./club_book_search_controller"
import FlashNotificationsController from "./flash_notifications_controller"

application.register("search", SearchController)
application.register("progress-bar", ProgressBarController)
application.register("quick-add", QuickAddController)
application.register("isbn-scanner", IsbnScannerController)
application.register("navbar", NavbarController)
application.register("nav-menu", NavMenuController)
application.register("notification-dropdown", NotificationDropdownController)
application.register("account-dropdown", AccountDropdownController)
application.register("book-picker", BookPickerController)
application.register("submit-on-change", SubmitOnChangeController)
application.register("review-composer", ReviewComposerController)
application.register("my-log-carousel", MyLogCarouselController)
application.register("profile-photo", ProfilePhotoController)
application.register("select-dropdown", SelectDropdownController)
application.register("club-book-search", ClubBookSearchController)
application.register("flash-notifications", FlashNotificationsController)
