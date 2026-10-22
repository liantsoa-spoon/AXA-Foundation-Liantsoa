# Commands

| Task                | Command                                          | Scope         |
| -------------------- | ------------------------------------------------- | -------------- |
| Install              | npm install                                        | Tooling        |
| Lint                 | npm run lint                                       | Aura, LWC      |
| Test                 | npm run test:unit                                  | LWC            |
| Test one component   | npx sfdx-lwc-jest -- --findRelatedTests <path>   | LWC            |
| Format               | npm run prettier                                   | LWC, metadata  |

Apex has no local lint or test. Apex tests run against an org.

## Org and deployment

Work against a sandbox, never production. Pass --target-org explicitly, since this repository
sets no default org.

### Read-only. No effect on the org.

| Task              | Command            |
| ------------------ | ------------------- |
| Inspect orgs       | sf org list        |
| Show org details   | sf org display      |
| Query data         | sf data query       |

### These write to the org or the working tree. Run only when explicitly requested.

| Task                    | Command                                        |
| ------------------------ | ------------------------------------------------- |
| Retrieve metadata        | sf project retrieve start -m <type>:<name>       |
| Run Apex tests           | sf apex run test                                 |
| Validate a deployment    | sf project deploy validate                       |

### These change org metadata or data. Do not run or propose them without explicit approval.

| Task              | Command                                            |
| ------------------ | ---------------------------------------------------- |
| Deploy metadata    | sf project deploy start                             |
| Delete metadata    | sf project delete source                            |
| Modify records     | sf data create, sf data update, sf data delete     |

Never delete an org.
