# What this fork feeds SARM2, and what it does not

Upstream SARM2 was written for teleoperated robot episodes: a proprioceptive
state vector of joint angles, an action column, one task name per episode.
The MicroAGI corpus is head-mounted video of human hands. It has **no robot
proprioception and no actions**. This file records exactly how the gap is
bridged, because the mapping is not visible from a training config alone.

## `observation.state` — 12 numbers, wrist pose, not proprioception

The export (`research_plan/phase0_envsetup/microagi_to_lerobot.py`) writes a
12-dimensional vector per frame:

    left_x  left_y  left_z  left_rx  left_ry  left_rz
    right_x right_y right_z right_rx right_ry right_rz

It is the tracked pose of both wrists — translation in metres and rotation in
radians — expressed in the **colour camera optical frame**. Two consequences
follow, and neither applies to upstream SARM2:

* The camera is head-mounted and moves, so this is wrist pose *relative to a
  moving observer*. Head motion enters the state. A hand held still while the
  operator turns their head produces a changing state vector.
* Rotation and translation live on very different scales (per-episode standard
  deviations of roughly 0.5–2.3 rad against 0.04–0.10 m). Training standardises
  the vector with statistics fitted on training episodes only
  (`meta/state_norm.json`), so the scale difference is handled, but any code
  reading raw state must expect it.

`state_dim: 12` in every MicroAGI config. The upstream defaults in the model
constructors (14 for the reward model, 7 for the estimator) are for the robot
datasets and are always overridden here.

The `no_state: true` ablation zeroes this vector after normalisation. It is not
a curiosity: in the campaign-1.2 hyperparameter sweep, removing the state
scored slightly *better* than keeping it.

## `action` — a copy of the state column, read by nothing

The export writes `action` byte-identical to `observation.state`, purely to
satisfy the LeRobot and Being-H schemas, which require the field. The SARM2
converter (`microagi_to_sarm.py`) carries it into the training parquet as
`actions`, and the loader caches it into the batch. **No model or training
loop reads it**: neither `RewardTransformer`, nor `ActionTransformer` (whose
name refers to action *primitives*, not to this column), nor either workspace.
Verified on the campaign-1.2 dataset: the two columns are equal on every row.

So SARM2's observation-only property holds here trivially. There is no action
supervision, no inverse dynamics, no action loss. Do not read `actions` as a
signal; if a future model needs one, it has to come from somewhere else.

## `reward` — the progress target, not an environment reward

The converter writes progress in [0, 1] per frame into `reward`. Its meaning is
set by the dataset build, not by this code: for label-based datasets it is the
`time_linear` target of the annotation cue that became the episode. With
`use_future_step: true` the workspace trains on `1 - reward`, the remaining
fraction, and the reported progress is its complement.

## `act_pri` — the action primitive class per frame

An integer index into `model.task_list` (17 verbs plus `dummy`). It supervises
the estimator and, at reward-training time, selects the mixture-of-experts
gate. It comes from the verb map over annotation text, not from any sensor.

## What the export carries but SARM2 never sees

MANO hand keypoints, in three forms (world, camera frame, projected pixels),
and the task confidence and segment index. The converter drops them. Only the
front camera video, the 12-D wrist vector, the instruction text and the two
derived columns above reach the model.

## Which data a run used

The training config names only a dataset id (`general.repo_id`). The lineage of
that dataset — label snapshot, which annotation track became episodes, the
filters — is recorded in the dataset's `meta/label_manifest.json`, in
`meta/episodes.jsonl` per episode, and in `logs/<campaign>/campaign.json`.
Configs written from campaign 1.3 onward also carry a `provenance` block so the
config alone answers the question.
