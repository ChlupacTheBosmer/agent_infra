# Projects Index

All active and archived projects. Each project has its own subdirectory.

## Active projects

| Project | Goal | Started | Last updated |
|---------|------|---------|-------------|
| (none yet) | | | |

## Paused projects

| Project | Last state | Paused since |
|---------|-----------|-------------|
| (none yet) | | |

## Completed / archived projects

| Project | Outcome | Completed |
|---------|---------|-----------|
| (none yet) | | |

## Adding a new project

1. Create `projects/<project-name>/` directory
2. Copy `vault-template/agents/templates/project-index.md` to `projects/<project-name>/INDEX.md` and fill it in
3. Create `projects/<project-name>/CHANGELOG.md` (start with a first entry)
4. Create `projects/<project-name>/context/` directory for detail files
5. Add a row to this index and to `000-INDEX.md`
6. Run `librarian-retrieve.sh "<first task>" <project-name>` to generate your first briefing
