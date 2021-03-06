import React, { useEffect, useContext, useState } from 'react';
import { ButtonStateLookup, CheckedExecutionCycle } from './ControlPanel';
import { Loader } from '../Loader';
import { ExecutionCycleStatus, Project } from '../domain';
import { ApiFactory } from '../api';
import styles from './ExecutionCycleGrid.module.scss';
import { FixedDate } from './FixedDate';

export interface ExecutionCycleGridProps {
  executionCycles: CheckedExecutionCycle[];
  setExecutionCycles: React.Dispatch<React.SetStateAction<CheckedExecutionCycle[]>>;
  reloadGrid: boolean;
  viewTrash: boolean;
  setReloadGrid: React.Dispatch<React.SetStateAction<boolean>>;
  setGridButtonStates: React.Dispatch<React.SetStateAction<ButtonStateLookup>>;
  gridButtonStates: ButtonStateLookup;
  project: Project;
}

export const ExecutionCycleGrid: React.FC<ExecutionCycleGridProps> = (props) => {
  const {
    executionCycles,
    setExecutionCycles,
    reloadGrid,
    setReloadGrid,
    viewTrash,
    setGridButtonStates,
    gridButtonStates,
    project
  } = props;

  const [selectAll, setSelectAll] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    console.debug('ExecutionCycleGrid#useEffect(reloadGrid, project)');
    if (project.interimState !== undefined) return;

    ApiFactory()
      .executionCycles()
      .list(project.id)
      .then((fetchedCycles) => {
        setExecutionCycles(
          fetchedCycles
            .map<CheckedExecutionCycle>(exCycle => ({
              ...exCycle,
              checked: exCycle.stoppedAt ? false : null
            }))
            .sort((a, b) => (b.startedAt.getTime() - a.startedAt.getTime()))
        );

        setSelectAll(false);
      })
      .then(() => setLoading(false))
      .then(() => setReloadGrid(false));
  }, [reloadGrid, project]);

  useEffect(() => {
    console.debug('ExecutionCycleGrid#useEffect(executionCycles)');
    if (executionCycles.some((exCycle) => exCycle.checked)) {
      setGridButtonStates({ ...gridButtonStates, report: false, export: false });
    } else {
      setGridButtonStates({ ...gridButtonStates, report: true, export: true });
    }

    if (
      executionCycles.length &&
      executionCycles.every((exCycle) => !exCycle.stoppedAt || exCycle.checked) &&
      (executionCycles.length > 1 || executionCycles[0].stoppedAt)
    ) {
      setSelectAll(true);
    } else {
      setSelectAll(false);
    }
  }, [executionCycles]);

  const handleSelectAll = () => {
    setSelectAll(!selectAll);
    setExecutionCycles(executionCycles.map((exCycle) => ({ ...exCycle, checked: !selectAll })));
  };

  const toggleCheck = (id: number) => {
    return () => {
      setExecutionCycles(executionCycles.map((exCycle) => {
        if (exCycle.id !== id) return exCycle;
        return { ...exCycle, checked: !exCycle.checked };
      }));
    };
  };

  const trashHandler = (exCid: number) => () => {
    setExecutionCycles(executionCycles.filter((x) => x.id !== exCid));
    setGridButtonStates({...gridButtonStates, trash: true});
    ApiFactory()
      .executionCycles()
      .update(exCid, project.id, {status: (viewTrash ? ExecutionCycleStatus.STOPPED : ExecutionCycleStatus.EXCLUDED)})
      .then(() => setReloadGrid(true))
      .then(() => setGridButtonStates({...gridButtonStates, trash: false}));
  };

  const shownCycles = executionCycles.filter((x) => viewTrash ?
                                                    x.status === ExecutionCycleStatus.EXCLUDED :
                                                    x.status !== ExecutionCycleStatus.EXCLUDED);

  const dateNow = new FixedDate(new Date());

  return (
    <div className={`${styles.scrollableTable}`}>
      <table className="table is-fullwidth is-striped">
        <thead>
          <tr>
            <th className={styles.narrow}><input type="checkbox" checked={selectAll} onChange={handleSelectAll} disabled={viewTrash || loading || executionCycles.length === 0} /></th>
            <th>Threads</th>
            <th className="is-gtk">90th Percentile (ms)</th>
            <th className="is-gtk">Throughput (tps)</th>
            <th>Started</th>
            <th>Duration (mins)</th>
            <th className={`${styles.narrow} is-gtk`}></th>
          </tr>
        </thead>
        {loading ? <tbody><tr><td colSpan={7}><Loader /></td></tr></tbody> : (
        <tbody>
          {shownCycles.length > 0 ?
          shownCycles.map(({id, threadsCount, responseTime, throughput, startedAt, stoppedAt, checked}) => (
          <tr key={id} className={stoppedAt ? undefined : 'notification is-warning'}>
            <td>{stoppedAt && !viewTrash ? <input type="checkbox" checked={checked || false} onChange={toggleCheck(id)}/> : null}</td>
            <td>{threadsCount}</td>
            <td className="is-gtk">{responseTime}</td>
            <td className="is-gtk">{throughput && new Number(throughput).toFixed(2)}</td>
            <td title={startedAt.toDateString()}>{dateNow.formatDistance(startedAt)}</td>
            <td>{stoppedAt ? dateDiff(stoppedAt, startedAt) : ''}</td>
            <td className="is-gtk">
            {stoppedAt ?
              <a className="is-danger" onClick={trashHandler(id)}>
              {viewTrash ?
                <i className="fas fa-undo"></i> :
                <i className="fas fa-trash"></i>
              }
              </a> :
              null
            }
            </td>
          </tr>)) :
          (<tr>
            <td colSpan={7}>
              <div className="notification is-info">
                {viewTrash ? "No items in trash." : "No tests to show."}
              </div>
            </td>
          </tr>)}
        </tbody>)}
      </table>
    </div>
  );
}

function dateDiff(date1: Date, date2: Date) {
  return Math.round((date1.getTime() - date2.getTime()) / 60000);
}
