// PM2 Ecosystem Config — SecureChat Backend
// Usage:
//   pm2 start ecosystem.config.js          (first time)
//   pm2 restart securechat-backend         (after deploy)
//   pm2 save                               (persist across reboots)
//   pm2 startup                            (enable auto-start on boot)

module.exports = {
  apps: [
    {
      name: "securechat-backend",
      script: "./backend/src/index.js",  // adjust if your entry point differs
      cwd: "/opt/securechat",
      instances: "max",      // use all CPU cores
      exec_mode: "cluster",  // cluster mode for load balancing
      watch: false,          // never watch in production

      // Environment loaded from SSM at startup via /opt/securechat/scripts/load-env.sh
      // DO NOT put secrets directly here — this file is committed to git
      env: {
        NODE_ENV: "production",
        PORT: 3000,
      },

      // Logging
      out_file: "/var/log/securechat/app-out.log",
      error_file: "/var/log/securechat/app-err.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,

      // Restart policy
      max_restarts: 10,
      restart_delay: 4000,   // ms
      min_uptime: "5s",
      max_memory_restart: "512M",

      // Graceful shutdown
      kill_timeout: 5000,
      listen_timeout: 8000,
      shutdown_with_message: true,
    },
  ],
};
