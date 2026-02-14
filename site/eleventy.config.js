import postcss from "postcss";
import tailwindcss from "@tailwindcss/postcss";
import cssnano from "cssnano";
import { readFileSync } from "fs";

export default function (eleventyConfig) {
  // Passthrough copies
  eleventyConfig.addPassthroughCopy("src/assets/js");
  eleventyConfig.addPassthroughCopy("src/examples/**/*.yml");

  // CSS processing via PostCSS + Tailwind
  eleventyConfig.addTemplateFormats("css");
  eleventyConfig.addExtension("css", {
    outputFileExtension: "css",
    compile: async function (inputContent, inputPath) {
      if (!inputPath.includes("main.css")) return;
      return async () => {
        const plugins = [tailwindcss()];
        if (process.env.NODE_ENV === "production") {
          plugins.push(cssnano());
        }
        const result = await postcss(plugins).process(inputContent, {
          from: inputPath,
        });
        return result.css;
      };
    },
  });

  // Watch targets
  eleventyConfig.addWatchTarget("src/assets/css/");
  eleventyConfig.addWatchTarget("src/assets/js/");

  // Filters
  eleventyConfig.addFilter("year", () => new Date().getFullYear());

  // Shortcodes
  eleventyConfig.addShortcode("year", () => `${new Date().getFullYear()}`);

  // pathPrefix for GitHub Pages
  const pathPrefix = process.env.GITHUB_ACTIONS
    ? "/rails-migration-guard/"
    : "/";

  return {
    dir: {
      input: "src",
      output: "dist",
      includes: "_includes",
      data: "_data",
    },
    templateFormats: ["njk", "md", "html"],
    htmlTemplateEngine: "njk",
    markdownTemplateEngine: "njk",
    pathPrefix,
  };
}
