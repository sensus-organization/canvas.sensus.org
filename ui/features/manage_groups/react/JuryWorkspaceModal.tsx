import React, {useState} from 'react'
import type {Root} from 'react-dom/client'
import {render} from '@canvas/react'
import {useScope as createI18nScope} from '@canvas/i18n'
import {Modal} from '@instructure/ui-modal'
import {View} from '@instructure/ui-view'
import {Heading} from '@instructure/ui-heading'
import {Button, CloseButton} from '@instructure/ui-buttons'
import {SimpleSelect} from '@instructure/ui-simple-select'
import {TextInput} from '@instructure/ui-text-input'
import {Checkbox} from '@instructure/ui-checkbox'
import {Alert} from '@instructure/ui-alerts'

const I18n = createI18nScope('groups')

export type JuryAssignment = {id: number; title: string}
export type JuryMember = {id: number; name: string}

export type JuryWorkspaceSelection = {
  assignmentId: number
  label: string
  jurorIds: number[]
}

type Props = {
  assignments: JuryAssignment[]
  members: JuryMember[]
  onSubmit: (selection: JuryWorkspaceSelection) => void
  onDismiss: () => void
  closed?: boolean
}

export function JuryWorkspaceModal({assignments, members, onSubmit, onDismiss, closed}: Props) {
  const [assignmentId, setAssignmentId] = useState<string>(
    assignments[0] ? String(assignments[0].id) : '',
  )
  const [label, setLabel] = useState('')
  const [jurorIds, setJurorIds] = useState<number[]>([])

  const selected = assignments.find(a => String(a.id) === assignmentId)
  const canSubmit = assignmentId !== '' && jurorIds.length > 0

  const toggle = (id: number) =>
    setJurorIds(current =>
      current.includes(id) ? current.filter(existing => existing !== id) : [...current, id],
    )

  return (
    <Modal
      open={!closed}
      onDismiss={onDismiss}
      label={I18n.t('Create Jury group sets')}
      size="medium"
    >
      <Modal.Header>
        <CloseButton
          placement="end"
          offset="small"
          onClick={onDismiss}
          screenReaderLabel={I18n.t('Close')}
        />
        <Heading>{I18n.t('Create Jury group sets')}</Heading>
      </Modal.Header>
      <Modal.Body>
        {assignments.length === 0 ? (
          <Alert variant="warning">
            {I18n.t('No assignment in this course uses jury-calibrated grading yet.')}
          </Alert>
        ) : (
          <View as="div">
            <SimpleSelect
              renderLabel={I18n.t('Assignment')}
              value={assignmentId}
              onChange={(_e, data) => setAssignmentId(String(data.value))}
            >
              {assignments.map(assignment => (
                <SimpleSelect.Option
                  key={assignment.id}
                  id={`jury-assignment-${assignment.id}`}
                  value={String(assignment.id)}
                >
                  {assignment.title}
                </SimpleSelect.Option>
              ))}
            </SimpleSelect>

            <View as="div" margin="medium 0 0">
              <TextInput
                renderLabel={I18n.t('Group set label')}
                placeholder={selected?.title}
                value={label}
                onChange={(_e, value) => setLabel(value)}
                messages={[
                  {
                    type: 'hint',
                    text: I18n.t(
                      'Shown before each Jury member’s name. Defaults to the assignment title.',
                    ),
                  },
                ]}
              />
            </View>

            <View as="div" margin="medium 0 0">
              <Heading level="h4">{I18n.t('Jury members')}</Heading>
              {members.map(member => (
                <View as="div" key={member.id} margin="x-small 0 0">
                  <Checkbox
                    label={member.name}
                    checked={jurorIds.includes(member.id)}
                    onChange={() => toggle(member.id)}
                  />
                </View>
              ))}
            </View>
          </View>
        )}
      </Modal.Body>
      <Modal.Footer>
        <Button onClick={onDismiss}>{I18n.t('Cancel')}</Button>&nbsp;
        <Button
          color="primary"
          interaction={canSubmit ? 'enabled' : 'disabled'}
          onClick={() => onSubmit({assignmentId: Number(assignmentId), label, jurorIds})}
        >
          {I18n.t('Create')}
        </Button>
      </Modal.Footer>
    </Modal>
  )
}

export function renderJuryWorkspaceDialog(
  div: HTMLElement,
  assignments: JuryAssignment[],
  members: JuryMember[],
): Promise<JuryWorkspaceSelection | null> {
  let root: Root | null = null
  return new Promise(resolve => {
    const close = (result: JuryWorkspaceSelection | null) => {
      root?.render(
        <JuryWorkspaceModal
          assignments={assignments}
          members={members}
          onSubmit={() => {}}
          onDismiss={() => {}}
          closed={true}
        />,
      )
      resolve(result)
    }

    root = render(
      <JuryWorkspaceModal
        assignments={assignments}
        members={members}
        onSubmit={selection => close(selection)}
        onDismiss={() => close(null)}
      />,
      div,
    )
  })
}
