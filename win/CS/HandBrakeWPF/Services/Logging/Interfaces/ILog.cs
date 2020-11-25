﻿// --------------------------------------------------------------------------------------------------------------------
// <copyright file="ILog.cs" company="HandBrake Project (http://handbrake.fr)">
//   This file is part of the HandBrake source code - It may be used under the terms of the GNU General Public License.
// </copyright>
// <summary>
//   Defines the ILog type.
// </summary>
// --------------------------------------------------------------------------------------------------------------------

namespace HandBrakeWPF.Services.Logging.Interfaces
{
    using System;
    using System.Collections.Generic;

    using HandBrake.Worker.Logging.Models;

    using LogEventArgs = HandBrakeWPF.Services.Logging.EventArgs.LogEventArgs;

    /// <summary>
    /// The Log interface.
    /// </summary>
    public interface ILog
    {
        /// <summary>
        /// The message logged.
        /// </summary>
        event EventHandler<LogEventArgs> MessageLogged;

        /// <summary>
        /// The log reset event
        /// </summary>
        event EventHandler LogReset;

        /// <summary>
        /// An ID that allows this instance to be associated with an encode service implementation. 
        /// </summary>
        int LogId { get; }

        /// <summary>
        /// The filename this log service is outputting to.
        /// </summary>
        string FileName { get; }

        /// <summary>
        /// Enable logging for this worker process.
        /// </summary>
        /// <param name="filename">
        /// The filename.
        /// </param>
        /// <remarks>
        /// If this is not called, all log messages from libhb will be ignored.
        /// </remarks>
        void ConfigureLogging(string filename);

        /// <summary>
        /// Log a message.
        /// </summary>
        /// <param name="content">
        /// The content of the log message,
        /// </param>
        void LogMessage(string content);

        string GetFullLog();

        List<LogMessage> GetLogMessages();

        /// <summary>
        /// Empty the log cache and reset the log handler to defaults.
        /// </summary>
        void Reset();

        /// <summary>
        /// Add a Marker to this log service to make it easier to associate with an encode instance.
        /// </summary>
        /// <param name="id">An ID number from the underlying service.</param>
        void SetId(int id);
    }
}