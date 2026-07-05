ActiveSupport::Notifications.subscribe("discard.active_job") do |*, payload|
  job = payload[:job]
  error = payload[:error]

  SemanticLogger["JobErrorReporting"].warn(
    "Job discarded",
    job_class: job.class.name,
    job_id: job.job_id,
    queue_name: job.queue_name,
    arguments: job.arguments,
    error_class: error.class.name,
    error_message: error.message
  )
end

ActiveSupport::Notifications.subscribe("enqueue_retry.active_job") do |*, payload|
  job = payload[:job]
  error = payload[:error]
  wait = payload[:wait]

  SemanticLogger["JobErrorReporting"].warn(
    "Job failed, retrying",
    job_class: job.class.name,
    job_id: job.job_id,
    queue_name: job.queue_name,
    arguments: job.arguments,
    error_class: error.class.name,
    error_message: error.message,
    wait_seconds: wait
  )
end

ActiveSupport::Notifications.subscribe("retry_stopped.active_job") do |*, payload|
  job = payload[:job]
  error = payload[:error]

  SemanticLogger["JobErrorReporting"].error(
    "Job retries exhausted, giving up",
    job_class: job.class.name,
    job_id: job.job_id,
    queue_name: job.queue_name,
    arguments: job.arguments,
    error_class: error.class.name,
    error_message: error.message
  )
end

ActiveSupport::Notifications.subscribe("perform.active_job") do |*, payload|
  job = payload[:job]
  error = payload[:exception_object]

  next if error.nil?

  SemanticLogger["JobErrorReporting"].error(
    "Job failed with an unhandled error",
    job_class: job.class.name,
    job_id: job.job_id,
    queue_name: job.queue_name,
    arguments: job.arguments,
    error_class: error.class.name,
    error_message: error.message
  )
end
