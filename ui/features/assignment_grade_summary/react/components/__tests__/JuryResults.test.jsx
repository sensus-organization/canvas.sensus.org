import React from 'react'
import {fireEvent, render, waitFor} from '@testing-library/react'
import axios from '@canvas/axios'
import JuryResults from '../JuryResults'

vi.mock('@canvas/axios')

describe('JuryResults', () => {
  it('shows the calculation progress returned by the server', async () => {
    axios.get.mockResolvedValueOnce({
      data: {
        jury_grading_run: {
          id: '1',
          progress: {completion: 10, id: '99', workflow_state: 'running'},
          results: {},
          settings: {},
          workflow_state: 'running',
        },
        readiness: {issues: []},
      },
    })
    axios.get.mockResolvedValue({data: {completion: 10, workflow_state: 'running'}})

    const {getByLabelText} = render(<JuryResults assignment={{courseId: '2', gradesPublished: false, id: '3', title: 'Jury assignment'}} />)

    await waitFor(() => expect(getByLabelText('Calculation progress')).toHaveValue(10))
  })

  it('disables publishing after a successful publish', async () => {
    axios.get.mockResolvedValue({data: {readiness: {coverage: {}, issues: []}}})
    axios.post.mockResolvedValue({})
    vi.spyOn(window, 'confirm').mockReturnValue(true)

    const {getByRole} = render(<JuryResults assignment={{courseId: '2', gradesPublished: false, id: '3', title: 'Jury assignment'}} />)
    await waitFor(() => expect(axios.get).toHaveBeenCalled())

    const component = getByRole('button', {name: 'Publish adjusted grades'})
    // The public UI only enables publish once the server has completed results.
    // Set that state through the component's normal calculate response.
    axios.post.mockResolvedValueOnce({data: {id: '1', results: {teams: {}}, workflow_state: 'completed'}})
    fireEvent.click(getByRole('button', {name: 'Calculate jury results'}))
    await waitFor(() => expect(component).toBeEnabled())
    fireEvent.click(component)
    await waitFor(() => expect(component).toBeDisabled())
  })

  it('disables publishing when readiness has configuration errors', async () => {
    axios.get.mockResolvedValue({
      data: {
        jury_grading_run: {id: '1', results: {teams: {}}, workflow_state: 'completed'},
        readiness: {coverage: {}, issues: ['No active Jury members']},
      },
    })

    const {getByRole} = render(<JuryResults assignment={{courseId: '2', gradesPublished: false, id: '3', title: 'Jury assignment'}} />)

    await waitFor(() => expect(getByRole('button', {name: 'Publish adjusted grades'})).toBeDisabled())
  })
})
