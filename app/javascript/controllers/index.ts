// Register each Stimulus controller manually — esbuild has no importmap-style eager loading
import { application } from "./application"
import HelloController from "./hello_controller"
import SearchController from "./search_controller"

application.register("hello", HelloController)
application.register("search", SearchController)