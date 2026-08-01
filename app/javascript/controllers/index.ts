// Register each Stimulus controller manually — esbuild has no importmap-style eager loading
import { application } from "./application"
import HelloController from "./hello_controller"
import SearchController from "./search_controller"
import ProgressBarController from "./progress_bar_controller"
import QuickAddController from "./quick_add_controller"
import IsbnScannerController from "./isbn_scanner_controller"

application.register("hello", HelloController)
application.register("search", SearchController)
application.register("progress-bar", ProgressBarController)
application.register("quick-add", QuickAddController)
application.register("isbn-scanner", IsbnScannerController)