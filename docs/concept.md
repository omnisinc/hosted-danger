## Concept

## Main Features

- :rocket: Super Fast Danger Execution
- :rocket: Agressive Automations
- :rocket: Hide Github Token from Users

## Details of Improvements

### An Example of Legacy Pull Request Flow
<img src="https://user-images.githubusercontent.com/3483230/46455263-2b23ba00-c7e5-11e8-842d-180ac8503799.png" />

In this flow, the coder have to assign reviewers and merge pull request by self.
Also the coder have to wait completion of CI processes to check these statuses.
Even if there is notification for it, the coder have to go back to the pull request page at least.

### With Hosted Danger
<img src="https://user-images.githubusercontent.com/3483230/46455255-252dd900-c7e5-11e8-8b63-cd31e00c69dc.png" />

Assigning reviewers, checking CI statuses, and merging pull requests is done by Hosted Danger.
As you can see the coder and the reviewer just do what they should do.
The other boring stuff (assigning reviewers, checking CI statuses, merging pull requests) is done by Hosted Danger.
Hosted Danger creates free time for developers to do their tasks.

## Comparison with CI danger

Here we show the comparison of Hosted Danger and CI danger.

|               | Timing of execution   | Access to the source code and build products |
|---------------|-----------------------|----------------------------------------------|
| Hosted Danger | Interactively         | Limited                                      |
| CI danger     | End of the CI process | Full access                                  |

## How does it work concretely?
This image shows how the auto-merge works.

<img src="https://user-images.githubusercontent.com/3483230/51239174-fd413a80-19bb-11e9-9472-6fa33d6b14fa.gif" width="500px"/>

## Next Step
- [Launch Server](/docs/launch_server.md)
