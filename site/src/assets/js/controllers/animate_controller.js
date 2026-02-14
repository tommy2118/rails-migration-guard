import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("animate-slide-up");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.1, rootMargin: "0px 0px -50px 0px" }
    );

    this.element.querySelectorAll("[data-animate]").forEach((el) => {
      observer.observe(el);
    });
  }
}
