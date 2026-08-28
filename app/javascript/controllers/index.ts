// Register each Stimulus controller manually — esbuild has no importmap-style eager loading
import { application } from "./application"
import SearchController from "./search_controller"
import ProgressBarController from "./progress_bar_controller"
import QuickAddController from "./quick_add_controller"
import IsbnScannerController from "./isbn_scanner_controller"
import NavbarController from "./navbar_controller"
import BookPickerController from "./book_picker_controller"

application.register("search", SearchController)
application.register("progress-bar", ProgressBarController)
application.register("quick-add", QuickAddController)
application.register("isbn-scanner", IsbnScannerController)
application.register("navbar", NavbarController)
application.register("book-picker", BookPickerController)