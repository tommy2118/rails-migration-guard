import { Application } from "@hotwired/stimulus";
import MobileNavController from "./controllers/mobile_nav_controller.js";
import ToggleController from "./controllers/toggle_controller.js";
import AnimateController from "./controllers/animate_controller.js";

const app = Application.start();
app.register("mobile-nav", MobileNavController);
app.register("toggle", ToggleController);
app.register("animate", AnimateController);
