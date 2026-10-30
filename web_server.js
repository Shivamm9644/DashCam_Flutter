const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 8090;
const WEB_DIR = path.join(__dirname, 'build', 'web');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.wav': 'audio/wav',
  '.mp4': 'video/mp4',
  '.woff': 'application/font-woff',
  '.ttf': 'application/font-ttf',
  '.eot': 'application/vnd.ms-fontobject',
  '.otf': 'application/font-otf',
  '.wasm': 'application/wasm',
};

const server = http.createServer((req, res) => {
  let reqPath = req.url.split('?')[0];
  if (reqPath === '/' || reqPath === '') reqPath = '/index.html';

  // Direct APK download route
  if (reqPath === '/download/app.apk' || reqPath === '/download/app-release.apk') {
    const releaseApk = path.join(__dirname, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
    const debugApk = path.join(__dirname, 'build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk');
    const apkPath = fs.existsSync(releaseApk) ? releaseApk : debugApk;
    if (fs.existsSync(apkPath)) {
      res.writeHead(200, {
        'Content-Type': 'application/vnd.android.package-archive',
        'Content-Disposition': 'attachment; filename="Inurum_Dashcam_Client.apk"'
      });
      fs.createReadStream(apkPath).pipe(res);
      return;
    }
  }

  // Kill service worker caching
  if (reqPath.includes('flutter_service_worker.js')) {
    res.writeHead(404);
    res.end();
    return;
  }
  
  let filePath = path.join(WEB_DIR, reqPath);
  
  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      filePath = path.join(WEB_DIR, 'index.html');
    }
    
    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    
    fs.readFile(filePath, (readErr, content) => {
      if (readErr) {
        res.writeHead(500);
        res.end('Server Error');
        return;
      }
      res.writeHead(200, {
        'Content-Type': contentType,
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0',
        'Pragma': 'no-cache',
        'Expires': '0'
      });
      res.end(content);
    });
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`=================================================`);
  console.log(`FLUTTER DASHCAM WEB APP IS ONLINE!`);
  console.log(`Local Browser URL:  http://localhost:${PORT}`);
  console.log(`Network Mobile URL: http://192.168.1.12:${PORT}`);
  console.log(`=================================================`);
});
