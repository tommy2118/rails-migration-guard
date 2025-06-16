# Rails Migration Guard Documentation Site

This directory contains the GitHub Pages site for Rails Migration Guard.

## Local Development

To run the site locally:

```bash
# Using Python
python -m http.server 8000

# Or using Ruby
ruby -run -e httpd . -p 8000

# Or using Node.js
npx http-server -p 8000
```

Then visit http://localhost:8000

## Design Principles

The site follows Apple's design philosophy and Steve Schoger's principles:

- **Clean, minimal design** with plenty of whitespace
- **Clear visual hierarchy** using size, weight, and color
- **Subtle animations** that enhance rather than distract
- **High contrast** for readability
- **Consistent spacing** using a defined scale
- **Glass morphism** for the navigation bar
- **Gradient accents** used sparingly for CTAs

## Technology

- **TailwindCSS** via CDN for styling
- **Inter font** for a clean, modern look
- **Vanilla JavaScript** for interactions
- **Static HTML** for simplicity and performance

## Color Palette

- Primary: Purple gradient (#667eea to #764ba2)
- Text: 
  - Midnight (#0a0a0a) - primary text
  - Steel (#1d1d1f) - code blocks
  - Smoke (#86868b) - secondary text
- Background:
  - White (#ffffff) - main background
  - Cloud (#f5f5f7) - section backgrounds

## Deployment

The site is automatically deployed to GitHub Pages when changes are pushed to the main branch.

Access the live site at: https://tommy2118.github.io/rails-migration-guard/
