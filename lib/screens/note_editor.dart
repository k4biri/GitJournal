import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import 'package:gitjournal/core/md_yaml_doc.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/notes_folder_fs.dart';
import 'package:gitjournal/editors/checklist_editor.dart';
import 'package:gitjournal/editors/journal_editor.dart';
import 'package:gitjournal/editors/markdown_editor.dart';
import 'package:gitjournal/editors/raw_editor.dart';
import 'package:gitjournal/error_reporting.dart';
import 'package:gitjournal/state_container.dart';
import 'package:gitjournal/utils.dart';
import 'package:gitjournal/utils/logger.dart';
import 'package:gitjournal/widgets/folder_selection_dialog.dart';
import 'package:gitjournal/widgets/note_editor_selector.dart';
import 'package:gitjournal/widgets/note_tag_editor.dart';
import 'package:gitjournal/widgets/rename_dialog.dart';

class ShowUndoSnackbar {}

class NoteEditor extends StatefulWidget {
  final Note note;
  final NotesFolderFS notesFolder;
  final EditorType defaultEditorType;

  final String existingText;
  final List<String> existingImages;

  final Map<String, dynamic> newNoteExtraProps;

  NoteEditor.fromNote(this.note)
      : notesFolder = note.parent,
        defaultEditorType = null,
        existingText = null,
        existingImages = null,
        newNoteExtraProps = null;

  NoteEditor.newNote(
    this.notesFolder,
    this.defaultEditorType, {
    this.existingText,
    this.existingImages,
    this.newNoteExtraProps = const {},
  }) : note = null;

  @override
  NoteEditorState createState() {
    if (note == null) {
      return NoteEditorState.newNote(
        notesFolder,
        existingText,
        existingImages,
        newNoteExtraProps,
      );
    } else {
      return NoteEditorState.fromNote(note);
    }
  }
}

enum EditorType { Markdown, Raw, Checklist, Journal }

class NoteEditorState extends State<NoteEditor> {
  Note note;
  EditorType editorType = EditorType.Markdown;
  MdYamlDoc originalNoteData = MdYamlDoc();

  final _rawEditorKey = GlobalKey<RawEditorState>();
  final _markdownEditorKey = GlobalKey<MarkdownEditorState>();
  final _checklistEditorKey = GlobalKey<ChecklistEditorState>();
  final _journalEditorKey = GlobalKey<JournalEditorState>();

  bool get _isNewNote {
    return widget.note == null;
  }

  NoteEditorState.newNote(
    NotesFolderFS folder,
    String existingText,
    List<String> existingImages,
    Map<String, dynamic> extraProps,
  ) {
    note = Note.newNote(folder, extraProps: extraProps);
    if (existingText != null) {
      note.body = existingText;
    }

    if (existingImages != null) {
      for (var imagePath in existingImages) {
        try {
          var file = File(imagePath);
          note.addImageSync(file);
        } catch (e) {
          Log.e(e);
        }
      }
    }
  }

  NoteEditorState.fromNote(this.note) {
    originalNoteData = MdYamlDoc.from(note.data);
  }

  @override
  void initState() {
    super.initState();
    if (widget.defaultEditorType != null) {
      editorType = widget.defaultEditorType;
    } else {
      switch (note.type) {
        case NoteType.Journal:
          editorType = EditorType.Journal;
          break;
        case NoteType.Checklist:
          editorType = EditorType.Checklist;
          break;
        case NoteType.Unknown:
          editorType = widget.notesFolder.config.defaultEditor;
          break;
      }
    }

    // Txt files
    if (note.fileFormat == NoteFileFormat.Txt &&
        editorType == EditorType.Markdown) {
      editorType = EditorType.Raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        var savedNote = await _saveNote(_getNoteFromEditor());
        return savedNote;
      },
      child: _getEditor(),
    );
  }

  Widget _getEditor() {
    switch (editorType) {
      case EditorType.Markdown:
        return MarkdownEditor(
          key: _markdownEditorKey,
          note: note,
          noteModified: _noteModified(note),
          noteDeletionSelected: _noteDeletionSelected,
          noteEditorChooserSelected: _noteEditorChooserSelected,
          exitEditorSelected: _exitEditorSelected,
          renameNoteSelected: _renameNoteSelected,
          editTagsSelected: _editTagsSelected,
          moveNoteToFolderSelected: _moveNoteToFolderSelected,
          discardChangesSelected: _discardChangesSelected,
          isNewNote: _isNewNote,
        );
      case EditorType.Raw:
        return RawEditor(
          key: _rawEditorKey,
          note: note,
          noteModified: _noteModified(note),
          noteDeletionSelected: _noteDeletionSelected,
          noteEditorChooserSelected: _noteEditorChooserSelected,
          exitEditorSelected: _exitEditorSelected,
          renameNoteSelected: _renameNoteSelected,
          editTagsSelected: _editTagsSelected,
          moveNoteToFolderSelected: _moveNoteToFolderSelected,
          discardChangesSelected: _discardChangesSelected,
          isNewNote: _isNewNote,
        );
      case EditorType.Checklist:
        return ChecklistEditor(
          key: _checklistEditorKey,
          note: note,
          noteModified: _noteModified(note),
          noteDeletionSelected: _noteDeletionSelected,
          noteEditorChooserSelected: _noteEditorChooserSelected,
          exitEditorSelected: _exitEditorSelected,
          renameNoteSelected: _renameNoteSelected,
          editTagsSelected: _editTagsSelected,
          moveNoteToFolderSelected: _moveNoteToFolderSelected,
          discardChangesSelected: _discardChangesSelected,
          isNewNote: _isNewNote,
        );
      case EditorType.Journal:
        return JournalEditor(
          key: _journalEditorKey,
          note: note,
          noteModified: _noteModified(note),
          noteDeletionSelected: _noteDeletionSelected,
          noteEditorChooserSelected: _noteEditorChooserSelected,
          exitEditorSelected: _exitEditorSelected,
          renameNoteSelected: _renameNoteSelected,
          editTagsSelected: _editTagsSelected,
          moveNoteToFolderSelected: _moveNoteToFolderSelected,
          discardChangesSelected: _discardChangesSelected,
          isNewNote: _isNewNote,
        );
    }
    return null;
  }

  void _noteEditorChooserSelected(Note _note) async {
    var newEditorType = await showDialog<EditorType>(
      context: context,
      builder: (BuildContext context) {
        return NoteEditorSelector(editorType, _note.fileFormat);
      },
    );

    if (newEditorType != null) {
      setState(() {
        note = _note;
        editorType = newEditorType;
      });
    }
  }

  void _exitEditorSelected(Note note) async {
    var saved = await _saveNote(note);
    if (saved) {
      Navigator.pop(context);
    }
  }

  void _renameNoteSelected(Note _note) async {
    var fileName = await showDialog(
      context: context,
      builder: (_) => RenameDialog(
        oldPath: note.filePath,
        inputDecoration: 'File Name',
        dialogTitle: "Rename File",
      ),
    );
    if (fileName is String) {
      if (_isNewNote) {
        setState(() {
          note = _note;
          note.rename(fileName);
        });
        return;
      }
      var container = Provider.of<StateContainer>(context, listen: false);
      container.renameNote(note, fileName);
    }
  }

  void _noteDeletionSelected(Note note) {
    if (_isNewNote && !_noteModified(note)) {
      Navigator.pop(context);
      return;
    }

    showDialog(context: context, builder: _buildAlertDialog);
  }

  void _deleteNote(Note note) {
    if (_isNewNote) {
      return;
    }

    var stateContainer = Provider.of<StateContainer>(context, listen: false);
    stateContainer.removeNote(note);
  }

  Widget _buildAlertDialog(BuildContext context) {
    return AlertDialog(
      title: const Text('Do you want to delete this note?'),
      actions: <Widget>[
        FlatButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep Writing'),
        ),
        FlatButton(
          onPressed: () {
            _deleteNote(note);

            Navigator.pop(context); // Alert box

            if (_isNewNote) {
              Navigator.pop(context); // Note Editor
            } else {
              Navigator.pop(context, ShowUndoSnackbar()); // Note Editor
            }
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }

  bool _noteModified(Note note) {
    if (_isNewNote) {
      return note.title.isNotEmpty || note.body.isNotEmpty;
    }

    if (note.data != originalNoteData) {
      var newSimplified = MdYamlDoc.from(note.data);
      newSimplified.props.remove(note.noteSerializer.settings.modifiedKey);
      newSimplified.body = newSimplified.body.trim();

      var originalSimplified = MdYamlDoc.from(originalNoteData);
      originalSimplified.props.remove(note.noteSerializer.settings.modifiedKey);
      originalSimplified.body = originalSimplified.body.trim();

      bool hasBeenModified = newSimplified != originalSimplified;
      if (hasBeenModified) {
        Log.d("Note modified");
        Log.d("Original: $originalSimplified");
        Log.d("New: $newSimplified");
        return true;
      }
    }
    return false;
  }

  // Returns bool indicating if the note was successfully saved
  Future<bool> _saveNote(Note note) async {
    if (!_noteModified(note)) return true;

    Log.d("Note modified - saving");
    try {
      var stateContainer = Provider.of<StateContainer>(context, listen: false);
      _isNewNote
          ? await stateContainer.addNote(note)
          : await stateContainer.updateNote(note);
    } catch (e, stackTrace) {
      logException(e, stackTrace);
      Clipboard.setData(ClipboardData(text: note.serialize()));

      await showAlertDialog(
        context,
        tr("editors.common.saveNoteFailed.title"),
        tr("editors.common.saveNoteFailed.message"),
      );
      return false;
    }

    return true;
  }

  Note _getNoteFromEditor() {
    switch (editorType) {
      case EditorType.Markdown:
        return _markdownEditorKey.currentState.getNote();
      case EditorType.Raw:
        return _rawEditorKey.currentState.getNote();
      case EditorType.Checklist:
        return _checklistEditorKey.currentState.getNote();
      case EditorType.Journal:
        return _journalEditorKey.currentState.getNote();
    }
    return null;
  }

  void _moveNoteToFolderSelected(Note note) async {
    var destFolder = await showDialog<NotesFolderFS>(
      context: context,
      builder: (context) => FolderSelectionDialog(),
    );
    if (destFolder != null) {
      if (_isNewNote) {
        note.parent = destFolder;
        setState(() {});
      } else {
        var stateContainer =
            Provider.of<StateContainer>(context, listen: false);
        stateContainer.moveNote(note, destFolder);
      }
    }
  }

  void _discardChangesSelected(Note note) {
    if (_noteModified(note)) {
      note.data = originalNoteData;
    }

    Navigator.pop(context);
  }

  void _editTagsSelected(Note _note) async {
    Log.i("Note Tags: ${_note.tags}");

    final rootFolder = Provider.of<NotesFolderFS>(context);
    var allTags = rootFolder.getNoteTagsRecursively();
    Log.i("All Tags: $allTags");

    var route = MaterialPageRoute(
      builder: (context) => NoteTagEditor(
        selectedTags: note.tags,
        allTags: allTags,
      ),
      settings: const RouteSettings(name: '/editTags/'),
    );
    var newTags = await Navigator.of(context).push(route);
    assert(newTags != null);

    Function eq = const SetEquality().equals;
    if (!eq(note.tags, newTags)) {
      setState(() {
        Log.i("Settings tags to: $newTags");
        note.tags = newTags;
      });
    }
  }
}
