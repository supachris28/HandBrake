﻿// --------------------------------------------------------------------------------------------------------------------
// <copyright file="LogInstanceManager.cs" company="HandBrake Project (http://handbrake.fr)">
//   This file is part of the HandBrake source code - It may be used under the terms of the GNU General Public License.
// </copyright>
// <summary>
// </summary>
// --------------------------------------------------------------------------------------------------------------------

namespace HandBrakeWPF.Services.Logging
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Linq;

    using HandBrakeWPF.Services.Logging.Interfaces;

    public class LogInstanceManager : ILogInstanceManager
    {
        private readonly object instanceLock = new object();
        private Dictionary<string, ILog> logInstances = new Dictionary<string, ILog>();
        
        public event EventHandler NewLogInstanceRegistered;

        public string ApplicationAndScanLog { get; private set; }

        public ILog MasterLogInstance { get; private set; }

        public void Register(string filename, ILog log, bool isMaster)
        {
            lock (this.instanceLock)
            {
                if (string.IsNullOrEmpty(this.ApplicationAndScanLog))
                {
                    // The application startup sets the initial log file.
                    this.ApplicationAndScanLog = filename;
                }

                this.logInstances.Add(filename, log);

                if (isMaster)
                {
                    this.MasterLogInstance = log;
                }
            }

            this.OnNewLogInstanceRegistered();
        }

        public void Deregister(string filename)
        {
            lock (this.instanceLock)
            {
                if (this.logInstances.ContainsKey(filename))
                {
                    this.logInstances.Remove(filename);
                }
            }

            this.OnNewLogInstanceRegistered();
        }

        public List<string> GetLogFiles()
        {
            lock (this.instanceLock)
            {
                List<string> encodeLogs = this.logInstances.Keys.Where(s => !s.Contains("main")).OrderBy(s => s).ToList();

                List<string> finalList = new List<string>();
                if (this.MasterLogInstance != null)
                {
                    finalList.Add(Path.GetFileName(this.MasterLogInstance.FileName));
                }

                finalList.AddRange(encodeLogs);

                return finalList;
            }
        }

        public ILog GetLogInstance(string filename)
        {
            lock (this.instanceLock)
            {
                if (string.IsNullOrEmpty(filename))
                {
                    return null;
                }

                ILog logger;
                if (this.logInstances.TryGetValue(filename, out logger))
                {
                    return logger;
                }
            }

            return null;
        }

        protected virtual void OnNewLogInstanceRegistered()
        {
            this.NewLogInstanceRegistered?.Invoke(this, System.EventArgs.Empty);
        }
    }
}
