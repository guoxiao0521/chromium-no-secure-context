const http = require("http");
const fs = require("fs");
const path = require("path");

const host = process.env.HOST || "127.0.0.1";
const port = Number(process.env.PORT || "8080");
const pageFileName = "test-http-apis.html";
const pageFilePath = path.join(__dirname, pageFileName);

function writeHtmlResponse(response, statusCode, body) {
  response.writeHead(statusCode, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(body);
}

const server = http.createServer((request, response) => {
  const requestPath = new URL(request.url, `http://${request.headers.host}`).pathname;
  const isPageRequest = requestPath === "/" || requestPath === `/${pageFileName}`;

  if (!isPageRequest) {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not Found");
    return;
  }

  fs.readFile(pageFilePath, "utf8", (error, htmlContent) => {
    if (error) {
      writeHtmlResponse(response, 500, `<h1>500</h1><pre>${String(error)}</pre>`);
      return;
    }
    writeHtmlResponse(response, 200, htmlContent);
  });
});

server.listen(port, host, () => {
  console.log(`HTTP test server running at http://${host}:${port}`);
  console.log(`Proxy page: http://${host}:${port}/`);
});
