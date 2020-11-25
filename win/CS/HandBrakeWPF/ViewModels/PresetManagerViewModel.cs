﻿// --------------------------------------------------------------------------------------------------------------------
// <copyright file="PresetManagerViewModel.cs" company="HandBrake Project (http://handbrake.fr)">
//   This file is part of the HandBrake source code - It may be used under the terms of the GNU General Public License.
// </copyright>
// <summary>
//   Defines the PresetManagerViewModel type.
// </summary>
// --------------------------------------------------------------------------------------------------------------------

namespace HandBrakeWPF.ViewModels
{
    using System.Collections.Generic;
    using System.ComponentModel;
    using System.Diagnostics;
    using System.Linq;
    using System.Windows;

    using Caliburn.Micro;

    using HandBrakeWPF.Factories;
    using HandBrakeWPF.Model.Picture;
    using HandBrakeWPF.Properties;
    using HandBrakeWPF.Services.Interfaces;
    using HandBrakeWPF.Services.Presets.Interfaces;
    using HandBrakeWPF.Services.Presets.Model;
    using HandBrakeWPF.Utilities;
    using HandBrakeWPF.ViewModels.Interfaces;
    using HandBrakeWPF.Views;

    using Microsoft.Win32;

    public class PresetManagerViewModel : ViewModelBase, IPresetManagerViewModel
    {
        private readonly IPresetService presetService;
        private readonly IErrorService errorService;
        private readonly IWindowManager windowManager;
        private readonly PresetDisplayCategory addNewCategory = new PresetDisplayCategory(Resources.AddPresetView_AddNewCategory, true, null);

        private IPresetObject selectedPresetCategory;
        private Preset selectedPreset;
        private PictureSettingsResLimitModes selectedPictureSettingsResLimitMode;

        public PresetManagerViewModel(IPresetService presetService, IErrorService errorService, IWindowManager windowManager)
        {
            this.presetService = presetService;
            this.errorService = errorService;
            this.windowManager = windowManager;
            this.Title = Resources.PresetManger_Title;
        }

        public bool IsOpen { get; set; }

        public IEnumerable<IPresetObject> PresetsCategories { get; set; }

        public List<PresetDisplayCategory> UserPresetCategories { get; set; }

        public PresetDisplayCategory SelectedUserPresetCategory
        {
            get
            {
                if (this.selectedPreset != null && this.PresetsCategories != null)
                {
                    return this.PresetsCategories.FirstOrDefault(s => s.Category == this.selectedPreset.Category) as PresetDisplayCategory;
                }

                return null;
            }

            set
            {
                if (this.selectedPreset != null && value != null  && value.Category != this.selectedPreset.Category)
                {
                    this.presetService.ChangePresetCategory(this.selectedPreset, value.Category);
                }
            }
        }

        public string SelectedItem { get; set; }

        public IPresetObject SelectedPresetCategory
        {
            get => this.selectedPresetCategory;
            set
            {
                if (!object.Equals(this.selectedPresetCategory, value))
                {
                    this.selectedPresetCategory = value;
                    this.NotifyOfPropertyChange(() => this.SelectedPresetCategory);

                    this.SelectedItem = value?.Category;
                    this.NotifyOfPropertyChange(() => this.SelectedItem);

                    this.selectedPreset = null;
                    this.NotifyOfPropertyChange(() => this.SelectedPreset);
                }
            }
        }

        public Preset SelectedPreset
        {
            get => this.selectedPreset;

            set
            {
                if (!object.Equals(this.selectedPreset, value))
                {
                    this.selectedPreset = value;
                    this.NotifyOfPropertyChange(() => this.SelectedPreset);

                    if (value != null)
                    {
                        this.SelectedItem = value.Name;
                        this.NotifyOfPropertyChange(() => this.SelectedItem);

                        this.IsBuildIn = value.IsBuildIn;

                        this.CustomWidth = value.Task.MaxWidth;
                        this.CustomHeight = value.Task.MaxHeight;
                        this.SetSelectedPictureSettingsResLimitMode();
                    }
                    else
                    {
                        this.selectedPresetCategory = null;
                        this.NotifyOfPropertyChange(() => this.SelectedPresetCategory);
                    }
                }

                this.NotifyOfPropertyChange(() => this.IsBuildIn);
                this.NotifyOfPropertyChange(() => this.SelectedUserPresetCategory);
                this.NotifyOfPropertyChange(() => this.IsPresetSelected);
                this.NotifyOfPropertyChange(() => this.UserPresetCategories);
            }
        }

        public bool IsBuildIn { get; private set; }

        public bool IsPresetSelected => this.SelectedPreset != null;

        public BindingList<PictureSettingsResLimitModes> ResolutionLimitModes => new BindingList<PictureSettingsResLimitModes>
                                                                                 {
                                                                                     PictureSettingsResLimitModes.None,
                                                                                     PictureSettingsResLimitModes.Size8K,
                                                                                     PictureSettingsResLimitModes.Size4K,
                                                                                     PictureSettingsResLimitModes.Size1080p,
                                                                                     PictureSettingsResLimitModes.Size720p,
                                                                                     PictureSettingsResLimitModes.Size576p,
                                                                                     PictureSettingsResLimitModes.Size480p,
                                                                                     PictureSettingsResLimitModes.Custom,
                                                                                 };

        public PictureSettingsResLimitModes SelectedPictureSettingsResLimitMode
        {
            get => this.selectedPictureSettingsResLimitMode;
            set
            {
                if (value == this.selectedPictureSettingsResLimitMode)
                {
                    return;
                }

                this.selectedPictureSettingsResLimitMode = value;
                this.NotifyOfPropertyChange(() => this.SelectedPictureSettingsResLimitMode);

                this.IsCustomMaxRes = value == PictureSettingsResLimitModes.Custom;
                this.NotifyOfPropertyChange(() => this.IsCustomMaxRes);

                // Enforce the new limit
                ResLimit limit = EnumHelper<PictureSettingsResLimitModes>.GetAttribute<ResLimit, PictureSettingsResLimitModes>(value);
                if (limit != null)
                {
                    this.CustomWidth = limit.Width;
                    this.CustomHeight = limit.Height;
                    this.NotifyOfPropertyChange(() => this.CustomWidth);
                    this.NotifyOfPropertyChange(() => this.CustomHeight);
                }

                if (value == PictureSettingsResLimitModes.None)
                {
                    this.CustomWidth = null;
                    this.CustomHeight = null;
                }
            }
        }

        public int? CustomWidth
        {
            get => this.selectedPreset?.Task.MaxWidth ?? null;
            set
            {
                if (value == this.selectedPreset.Task.MaxWidth)
                {
                    return;
                }

                this.selectedPreset.Task.MaxWidth = value;
                this.NotifyOfPropertyChange(() => this.CustomWidth);
            }
        }

        public int? CustomHeight
        {
            get => this.selectedPreset?.Task.MaxHeight ?? null;
            set
            {
                if (value == this.selectedPreset.Task.MaxHeight)
                {
                    return;
                }

                this.selectedPreset.Task.MaxHeight = value;
                this.NotifyOfPropertyChange(() => this.CustomHeight);
            }
        }

        public bool IsCustomMaxRes { get; private set; }

        public void SetupWindow()
        {
            this.PresetsCategories = this.presetService.Presets;
            this.NotifyOfPropertyChange(() => this.PresetsCategories);
            this.presetService.LoadCategoryStates();
            this.UserPresetCategories = presetService.GetPresetCategories(true).ToList(); // .Union(new List<PresetDisplayCategory> { addNewCategory }).ToList();
            this.presetService.PresetCollectionChanged += this.PresetService_PresetCollectionChanged;
        }

        public void DeletePreset()
        {
            if (this.selectedPreset != null)
            {
                if (this.selectedPreset.IsDefault)
                {
                    this.errorService.ShowMessageBox(
                      Resources.MainViewModel_CanNotDeleteDefaultPreset,
                      Resources.Warning,
                      MessageBoxButton.OK,
                      MessageBoxImage.Information);

                    return;
                }

                MessageBoxResult result =
                this.errorService.ShowMessageBox(
                   Resources.MainViewModel_PresetRemove_AreYouSure + this.selectedPreset.Name + " ?",
                   Resources.Question,
                   MessageBoxButton.YesNo,
                   MessageBoxImage.Question);

                if (result == MessageBoxResult.No)
                {
                    return;
                }

                this.presetService.Remove(this.selectedPreset);
                this.NotifyOfPropertyChange(() => this.PresetsCategories);
                this.SelectedPreset = this.presetService.DefaultPreset;
            }
            else
            {
                this.errorService.ShowMessageBox(Resources.Main_SelectPreset, Resources.Warning, MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        public void SetDefault()
        {
            if (this.selectedPreset != null)
            {
                this.presetService.SetDefault(this.selectedPreset);
                this.errorService.ShowMessageBox(string.Format(Resources.Main_NewDefaultPreset, this.selectedPreset.Name), Resources.Main_Presets, MessageBoxButton.OK, MessageBoxImage.Information);
            }
            else
            {
                this.errorService.ShowMessageBox(Resources.Main_SelectPreset, Resources.Warning, MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        public void Import()
        {
            OpenFileDialog dialog = new OpenFileDialog { Filter = "Preset Files|*.json;*.plist", CheckFileExists = true };
            bool? dialogResult = dialog.ShowDialog();
            if (dialogResult.HasValue && dialogResult.Value)
            {
                this.presetService.Import(dialog.FileName);
                this.NotifyOfPropertyChange(() => this.PresetsCategories);
            }
        }

        public void Export()
        {
            if (this.selectedPreset != null && !this.selectedPreset.IsBuildIn)
            {
                SaveFileDialog savefiledialog = new SaveFileDialog
                {
                    Filter = "json|*.json",
                    CheckPathExists = true,
                    AddExtension = true,
                    DefaultExt = ".json",
                    OverwritePrompt = true,
                    FilterIndex = 0
                };

                savefiledialog.ShowDialog();
                string filename = savefiledialog.FileName;

                if (!string.IsNullOrEmpty(filename))
                {
                    this.presetService.Export(savefiledialog.FileName, this.selectedPreset, HBConfigurationFactory.Create());
                }
            }
            else
            {
                this.errorService.ShowMessageBox(Resources.Main_SelectPreset, Resources.Warning, MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        public void ExportUserPresets()
        {
            SaveFileDialog savefiledialog = new SaveFileDialog
            {
                Filter = "json|*.json",
                CheckPathExists = true,
                AddExtension = true,
                DefaultExt = ".json",
                OverwritePrompt = true,
                FilterIndex = 0
            };

            savefiledialog.ShowDialog();
            string filename = savefiledialog.FileName;

            if (!string.IsNullOrEmpty(filename))
            {
                IList<PresetDisplayCategory> userPresets = this.presetService.GetPresetCategories(true);
                this.presetService.ExportCategories(savefiledialog.FileName, userPresets, HBConfigurationFactory.Create());
            }
        }

        public void DeleteBuiltInPresets()
        {
            List<Preset> allPresets = this.presetService.FlatPresetList;
            bool foundDefault = false;
            foreach (Preset preset in allPresets)
            {
                if (preset.IsBuildIn)
                {
                    if (preset.IsDefault)
                    {
                        foundDefault = true;
                    }

                    this.presetService.Remove(preset);
                }
            }

            if (foundDefault)
            {
                Preset preset = this.presetService.FlatPresetList.FirstOrDefault();
                if (preset != null)
                {
                    this.presetService.SetDefault(preset);
                    this.SelectedPreset = preset;
                }
            }

            this.NotifyOfPropertyChange(() => this.PresetsCategories);
        }

        public void ResetBuiltInPresets()
        {
            this.presetService.UpdateBuiltInPresets();

            this.NotifyOfPropertyChange(() => this.PresetsCategories);

            this.SetDefaultPreset();
            
            this.errorService.ShowMessageBox(Resources.Presets_ResetComplete, Resources.Presets_ResetHeader, MessageBoxButton.OK, MessageBoxImage.Information);
        }

        public void EditAudioDefaults()
        {
            if (this.selectedPreset == null)
            {
                return;
            }

            IAudioDefaultsViewModel audioDefaultsViewModel = new AudioDefaultsViewModel(this.selectedPreset.Task);
            audioDefaultsViewModel.ResetApplied();
            audioDefaultsViewModel.Setup(this.selectedPreset, this.selectedPreset.Task);

            this.windowManager.ShowDialog(audioDefaultsViewModel);
            if (audioDefaultsViewModel.IsApplied)
            {
                this.SelectedPreset.AudioTrackBehaviours = audioDefaultsViewModel.AudioBehaviours.Clone();
            }
        }

        public void EditSubtitleDefaults()
        {
            if (this.selectedPreset == null)
            {
                return;
            }

            ISubtitlesDefaultsViewModel subtitlesDefaultsViewModel = new SubtitlesDefaultsViewModel();
            subtitlesDefaultsViewModel.ResetApplied();
            SubtitlesDefaultsView view = new SubtitlesDefaultsView();
            view.DataContext = subtitlesDefaultsViewModel;
            view.ShowDialog();

            if (subtitlesDefaultsViewModel.IsApplied)
            {
                this.SelectedPreset.SubtitleTrackBehaviours = subtitlesDefaultsViewModel.SubtitleBehaviours.Clone();
            }
        }

        public void Close()
        {
            this.presetService.Save();
            this.IsOpen = false;
            this.presetService.PresetCollectionChanged -= this.PresetService_PresetCollectionChanged; 
        }

        public void SetCurrentPresetAsDefault()
        {
            if (this.SelectedPreset != null)
            {
                this.presetService.SetDefault(this.SelectedPreset);
            }
        }

        public void LaunchHelp()
        {
            Process.Start("https://handbrake.fr/docs/en/latest/advanced/custom-presets.html");
        }

        private void SetDefaultPreset()
        {
            // Preset Selection
            if (this.presetService.DefaultPreset != null)
            {
                PresetDisplayCategory category =
                    (PresetDisplayCategory)this.PresetsCategories.FirstOrDefault(
                        p => p.Category == this.presetService.DefaultPreset.Category);

                this.SelectedPresetCategory = category;
                this.SelectedPreset = this.presetService.DefaultPreset;
            }
        }

        private void SetSelectedPictureSettingsResLimitMode()
        {
            // Look for a matching resolution.
            foreach (PictureSettingsResLimitModes limit in EnumHelper<PictureSettingsResLimitModes>.GetEnumList())
            {
                ResLimit resLimit = EnumHelper<PictureSettingsResLimitModes>.GetAttribute<ResLimit, PictureSettingsResLimitModes>(limit);
                if (resLimit != null)
                {
                    if (resLimit.Width == this.CustomWidth && resLimit.Height == this.CustomHeight)
                    {
                        this.SelectedPictureSettingsResLimitMode = limit;
                        return;
                    }
                }
            }

            if (this.CustomWidth.HasValue || this.CustomHeight.HasValue)
            {
                this.SelectedPictureSettingsResLimitMode = PictureSettingsResLimitModes.Custom;
            }
            else
            {
                this.SelectedPictureSettingsResLimitMode = PictureSettingsResLimitModes.None;
            }
        }

        private void PresetService_PresetCollectionChanged(object sender, System.EventArgs e)
        {
            string presetName = this.selectedPreset?.Name; // Recording such that we can re-select

            this.PresetsCategories = this.presetService.Presets;
            this.UserPresetCategories = presetService.GetPresetCategories(true).ToList(); // .Union(new List<PresetDisplayCategory> { addNewCategory }).ToList();

            this.NotifyOfPropertyChange(() => this.PresetsCategories);
            this.NotifyOfPropertyChange(() => this.UserPresetCategories);
            this.NotifyOfPropertyChange(() => this.SelectedUserPresetCategory);

            // Reselect the preset as the object has changed due to the reload that occurred.
            if (!string.IsNullOrEmpty(presetName))
            {
                this.SelectedPreset = this.presetService.FlatPresetList.FirstOrDefault(s => s.Name == presetName);
            }
        }
    }
}
