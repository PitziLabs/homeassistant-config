/* Shared Mermaid init for kiosk library pages. Loaded AFTER
   assets/mermaid.min.js (the vendored global build), so `mermaid` exists.
   useMaxWidth:false lets the SVG scale up to fill the panel (see kiosk.css). */
mermaid.initialize({
  startOnLoad: true,
  theme: 'dark',
  securityLevel: 'loose',
  flowchart: { curve: 'basis', nodeSpacing: 45, rankSpacing: 70, htmlLabels: true, useMaxWidth: false },
  themeVariables: { fontSize: '22px', fontFamily: 'Segoe UI, Roboto, sans-serif' }
});
