// Register each Stimulus controller manually — esbuild has no importmap-style eager loading
import { application } from "./application"
import HelloController from "./hello_controller"

application.register("hello", HelloController)