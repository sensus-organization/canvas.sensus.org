import React from 'react'
import {render, screen, waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {JuryWorkspaceModal} from '../JuryWorkspaceModal'

const assignments = [
  {id: 52, title: 'Teams Results Document Submission - IN'},
  {id: 53, title: 'Teams Results Document Submission - TP'},
]
const members = [
  {id: 121, name: 'Jury 01'},
  {id: 122, name: 'Jury 02'},
]

function renderModal(overrides = {}) {
  const onSubmit = vi.fn()
  const onDismiss = vi.fn()
  render(
    <JuryWorkspaceModal
      assignments={assignments}
      members={members}
      onSubmit={onSubmit}
      onDismiss={onDismiss}
      {...overrides}
    />,
  )
  return {onSubmit, onDismiss}
}

describe('JuryWorkspaceModal', () => {
  it('cannot submit until at least one juror is picked', async () => {
    renderModal()

    expect(screen.getByRole('button', {name: 'Create'})).toBeDisabled()

    await userEvent.click(screen.getByLabelText('Jury 01'))

    await waitFor(() => expect(screen.getByRole('button', {name: 'Create'})).toBeEnabled())
  })

  it('returns the selected assignment, label and jurors', async () => {
    const {onSubmit} = renderModal()

    await userEvent.click(screen.getByLabelText('Jury 02'))
    await userEvent.type(screen.getByRole('textbox'), 'IN')
    await userEvent.click(screen.getByRole('button', {name: 'Create'}))

    expect(onSubmit).toHaveBeenCalledWith({assignmentId: 52, label: 'IN', jurorIds: [122]})
  })

  it('keeps a non-default assignment selected and submits it', async () => {
    const {onSubmit} = renderModal()

    await userEvent.click(screen.getByRole('combobox', {name: /Assignment/}))
    await userEvent.click(screen.getByText('Teams Results Document Submission - TP'))

    expect(screen.getByRole('combobox', {name: /Assignment/})).toHaveValue(
      'Teams Results Document Submission - TP',
    )

    await userEvent.click(screen.getByLabelText('Jury 01'))
    await userEvent.click(screen.getByRole('button', {name: 'Create'}))

    expect(onSubmit).toHaveBeenCalledWith({assignmentId: 53, label: '', jurorIds: [121]})
  })

  it('defaults the label to empty so the server falls back to the assignment title', async () => {
    const {onSubmit} = renderModal()

    await userEvent.click(screen.getByLabelText('Jury 01'))
    await userEvent.click(screen.getByRole('button', {name: 'Create'}))

    expect(onSubmit).toHaveBeenCalledWith({assignmentId: 52, label: '', jurorIds: [121]})
  })

  it('warns when the course has no jury-calibrated assignment', () => {
    renderModal({assignments: []})

    expect(
      screen.getByText('No assignment in this course uses jury-calibrated grading yet.'),
    ).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Create'})).toBeDisabled()
  })

  it('dismisses without a selection', async () => {
    const {onDismiss, onSubmit} = renderModal()

    await userEvent.click(screen.getByRole('button', {name: 'Cancel'}))

    expect(onDismiss).toHaveBeenCalled()
    expect(onSubmit).not.toHaveBeenCalled()
  })
})
