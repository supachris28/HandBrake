﻿// --------------------------------------------------------------------------------------------------------------------
// <copyright file="AboutViewModel.cs" company="HandBrake Project (http://handbrake.fr)">
//   This file is part of the HandBrake source code - It may be used under the terms of the GNU General Public License.
// </copyright>
// <summary>
//   The About View Model
// </summary>
// --------------------------------------------------------------------------------------------------------------------

namespace HandBrakeWPF.ViewModels
{
    using System;

    using HandBrake.Interop.Utilities;

    using HandBrakeWPF.Properties;
    using HandBrakeWPF.ViewModels.Interfaces;

    /// <summary>
    /// The About View Model
    /// </summary>
    public class AboutViewModel : ViewModelBase, IAboutViewModel
    {
        /// <summary>
        /// Initializes a new instance of the <see cref="AboutViewModel"/> class.
        /// </summary>
        public AboutViewModel()
        {
            this.Title = "About HandBrake";
        }

        /// <summary>
        /// Gets Version.
        /// </summary>
        public string Version
        {
            get
            {
                return string.Format("{0}", VersionHelper.GetVersion());
            }
        }

        public string License
        {
            get => string.Format("{0}{1}{1}{2}", Resources.About_Copyright, Environment.NewLine, Resources.About_GPL);
        }

        /// <summary>
        /// Close this window.
        /// </summary>
        public void Close()
        {
            this.TryClose();
        }
    }
}
